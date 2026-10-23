package auth_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"plany/internal/api/dto"
	"plany/internal/auth"
	"plany/internal/database/db"
	"plany/internal/validator"
)

func median(d []time.Duration) time.Duration {
	sort.Slice(d, func(i, j int) bool { return d[i] < d[j] })
	return d[len(d)/2]
}

// Enumeração por tempo: "e-mail inexistente" não pode ser bem mais rápido que "senha errada".
// Sem o hash falso, o primeiro caso pula o Argon2 e responde em ~1 ms contra dezenas de ms.
func TestDB_Service_Login_TimingDoesNotRevealUnknownEmail(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	svc := auth.NewService(repo, true)
	ctx := context.Background()

	email := uniqueEmail("timing")
	user, err := svc.Register(ctx, email, "timinguser", testPassword)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repo.DeleteUser(ctx, user.ID) })

	measure := func(email string) time.Duration {
		var ds []time.Duration
		for i := 0; i < 5; i++ {
			start := time.Now()
			_, err := svc.Login(ctx, email, "senha_errada_999", "s", time.Minute, time.Hour)
			ds = append(ds, time.Since(start))
			if !errors.Is(err, auth.ErrInvalidCredentials) {
				t.Fatalf("login(%s): err = %v, want ErrInvalidCredentials", email, err)
			}
		}
		return median(ds)
	}
	measure(email) // aquece conexão do pool e a memória
	wrong := measure(email)
	unknown := measure(uniqueEmail("ninguem"))

	if unknown < wrong/2 {
		t.Fatalf("e-mail inexistente responde em %v, senha errada em %v: dá para enumerar contas pelo tempo", unknown, wrong)
	}
}

// Maiúsculas/minúsculas: o e-mail é a mesma conta (CITEXT); o login funciona em qualquer caixa.
func TestDB_Service_Email_IsCaseInsensitive(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	svc := auth.NewService(repo, true)
	ctx := context.Background()

	email := strings.ToLower(uniqueEmail("caixa"))
	user, err := svc.Register(ctx, email, "ana", testPassword)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repo.DeleteUser(ctx, user.ID) })

	if _, err := svc.Register(ctx, strings.ToUpper(email), "outra", testPassword); !errors.Is(err, auth.ErrEmailAlreadyExists) {
		t.Fatalf("mesmo e-mail em maiúsculas deveria ser duplicado, err = %v", err)
	}
	if _, err := svc.Login(ctx, strings.ToUpper(email), testPassword, "s", time.Minute, time.Hour); err != nil {
		t.Fatalf("login com o e-mail em maiúsculas falhou: %v", err)
	}
}

// Decisão registrada: username é só nome de exibição, não identifica a conta nem é único.
// Se isso mudar (por exemplo @menções), a migration precisa de um índice único sobre a forma normalizada.
func TestDB_Service_Username_IsDisplayNameOnly(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	svc := auth.NewService(repo, true)
	ctx := context.Background()
	for i := 0; i < 2; i++ {
		u, err := svc.Register(ctx, uniqueEmail(fmt.Sprintf("nome%d", i)), "Ana", testPassword)
		if err != nil {
			t.Fatalf("registro %d com username repetido falhou: %v", i, err)
		}
		t.Cleanup(func() { _ = repo.DeleteUser(ctx, u.ID) })
	}
}

// Concorrência: N cadastros do mesmo e-mail ao mesmo tempo. Exatamente um vence; os outros
// recebem ErrEmailAlreadyExists (409), nunca um erro cru do banco (500).
func TestDB_Service_Register_ConcurrentSameEmail(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	svc := auth.NewService(repo, true)
	ctx := context.Background()
	email := uniqueEmail("corrida")

	const n = 8
	var wg sync.WaitGroup
	start := make(chan struct{})
	errs := make([]error, n)
	users := make([]*db.CreateUserRow, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			users[i], errs[i] = svc.Register(ctx, email, fmt.Sprintf("u%d", i), testPassword)
		}(i)
	}
	close(start)
	wg.Wait()

	wins := 0
	for i, err := range errs {
		switch {
		case err == nil:
			wins++
			u := users[i]
			t.Cleanup(func() { _ = repo.DeleteUser(ctx, u.ID) })
		case !errors.Is(err, auth.ErrEmailAlreadyExists):
			t.Errorf("goroutine %d: erro inesperado (viraria 500): %v", i, err)
		}
	}
	if wins != 1 {
		t.Fatalf("%d cadastros venceram, esperado exatamente 1", wins)
	}
}

// O mesmo pelo handler: o perdedor da corrida responde 409 email_already_exists.
func TestDB_Handler_Register_ConcurrentSameEmail_Returns409(t *testing.T) {
	h, repo, cleanup := setupTest(t, true)
	defer cleanup()
	email := uniqueEmail("corrida-h")

	const n = 6
	var wg sync.WaitGroup
	start := make(chan struct{})
	recs := make([]*httptest.ResponseRecorder, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			recs[i] = httptest.NewRecorder()
			h.Register(recs[i], protoRequest(t, http.MethodPost, "/auth/register/", &dto.RegisterInput{
				Email: email, Username: "corredor", Password: testPassword,
			}))
		}(i)
	}
	close(start)
	wg.Wait()

	created := 0
	for _, rec := range recs {
		switch rec.Code {
		case http.StatusCreated:
			created++
			var resp dto.RegisterResponse
			decodeBody(t, rec, &resp)
			id := resp.GetUser().GetId()
			t.Cleanup(func() { deleteUserByEmail(t, repo, email, id) })
		case http.StatusConflict:
			requireError(t, rec, http.StatusConflict, "email_already_exists")
		default:
			t.Errorf("status %d (%q): só 201 ou 409 são aceitáveis", rec.Code, rec.Body.String())
		}
	}
	if created != 1 {
		t.Fatalf("%d contas criadas, esperado 1", created)
	}
}

func deleteUserByEmail(t *testing.T, repo *db.Queries, email, _ string) {
	t.Helper()
	if u, err := repo.GetUserByEmail(context.Background(), email); err == nil {
		_ = repo.DeleteUser(context.Background(), u.ID)
	}
}

// Logout de ponta a ponta: depois dele, nem o access nem o refresh antigos valem.
func TestDB_Handler_Logout_InvalidatesAccessAndRefresh(t *testing.T) {
	h, repo, cleanup := setupTest(t, true)
	defer cleanup()
	u := registerUser(t, h, repo, "logout-e2e")
	access, refresh := loginUser(t, h, u)

	req := rawRequest(http.MethodPost, "/auth/logout/", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	req.AddCookie(refresh)
	rec := httptest.NewRecorder()
	h.Logout(rec, req)
	requireStatus(t, rec, http.StatusNoContent)

	// refresh token revogado não gera novo access token
	req = rawRequest(http.MethodPost, "/auth/refresh/", nil)
	req.AddCookie(refresh)
	rec = httptest.NewRecorder()
	h.Refresh(rec, req)
	requireStatus(t, rec, http.StatusUnauthorized)

	// access token revogado não abre /auth/me
	req = rawRequest(http.MethodGet, "/auth/me/", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	rec = httptest.NewRecorder()
	h.Me(rec, req)
	requireStatus(t, rec, http.StatusUnauthorized)

	// sair duas vezes (toque repetido) não vira 500
	req = rawRequest(http.MethodPost, "/auth/logout/", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	req.AddCookie(refresh)
	rec = httptest.NewRecorder()
	h.Logout(rec, req)
	if rec.Code >= 500 {
		t.Fatalf("segundo logout: %d", rec.Code)
	}
}

// Um refresh token não serve como access token e vice-versa não vira sessão nova depois do logout.
// (Hoje os dois são o mesmo tipo de token; este teste documenta o que é garantido: a revogação vale.)
func TestDB_Handler_Login_TwoSessionsAreIndependent(t *testing.T) {
	h, repo, cleanup := setupTest(t, true)
	defer cleanup()
	u := registerUser(t, h, repo, "duas-sessoes")
	accessA, refreshA := loginUser(t, h, u)
	_, refreshB := loginUser(t, h, u)

	req := rawRequest(http.MethodPost, "/auth/logout/", nil)
	req.Header.Set("Authorization", "Bearer "+accessA)
	req.AddCookie(refreshA)
	h.Logout(httptest.NewRecorder(), req)

	req = rawRequest(http.MethodPost, "/auth/refresh/", nil)
	req.AddCookie(refreshB)
	rec := httptest.NewRecorder()
	h.Refresh(rec, req)
	requireStatus(t, rec, http.StatusOK) // sair de um aparelho não derruba o outro
}

// Unicode no username: invisíveis, controle e formas diferentes do mesmo texto.
func TestValidateRegister_UnicodeUsernames(t *testing.T) {
	bad := map[string]string{
		"espaço de largura zero": "​​​",
		"zero-width no meio":     "an​a",
		"joiner":                 "a‍b‍c",
		"BOM":                    string(rune(0xFEFF)) + "ana",
		"controle":               "ana\x00",
		"newline":                "ana\nbob",
		"override bidi":          "ana‮evil",
		"espaço ideográfico":     "　　　",
		"espaço sem quebra":      "   ",
		"só marcas combinantes":  "́́́",
		"tag characters":         "ana\U000E0041",
	}
	for name, u := range bad {
		err := validator.ValidateRegister(&dto.RegisterInput{Email: "a@b.com", Username: u, Password: "senha_valida_123"})
		if err == nil {
			t.Errorf("%s (%q) foi aceito", name, u)
		}
	}
	good := []string{"José", "Zoë", "李雷明", "Ana Maria", "ação", "🙂ok"}
	for _, u := range good {
		if err := validator.ValidateRegister(&dto.RegisterInput{Email: "a@b.com", Username: u, Password: "senha_valida_123"}); err != nil {
			t.Errorf("%q recusado: %v", u, err)
		}
	}
}

// O limite de 3..32 conta caracteres (runes), não bytes: "李雷李" tem 3 caracteres e 9 bytes.
func TestValidateRegister_UsernameLengthCountsCharacters(t *testing.T) {
	ok := func(u string) bool {
		return validator.ValidateRegister(&dto.RegisterInput{Email: "a@b.com", Username: u, Password: "senha_valida_123"}) == nil
	}
	if !ok("李雷李") {
		t.Error("3 caracteres (9 bytes) deveria passar")
	}
	if !ok(strings.Repeat("é", 32)) {
		t.Error("32 caracteres (64 bytes) deveria passar")
	}
	if ok(strings.Repeat("é", 33)) {
		t.Error("33 caracteres deveria falhar")
	}
	if ok("éé") {
		t.Error("2 caracteres deveria falhar")
	}
}

// Normalização: "é" composto (U+00E9) e "e"+acento (U+0065 U+0301) são o mesmo nome e
// precisam ser gravados da mesma forma (NFC).
func TestValidator_NormalizeUsername(t *testing.T) {
	composed, decomposed := "José", "José"
	if validator.NormalizeUsername(composed) != validator.NormalizeUsername(decomposed) {
		t.Fatal("as duas formas de 'José' deveriam normalizar igual")
	}
	if got := validator.NormalizeUsername("  Ana  "); got != "Ana" {
		t.Errorf("espaços nas pontas: %q", got)
	}
	if got := validator.NormalizeUsername(decomposed); got != composed {
		t.Errorf("esperado NFC, veio %+q", got)
	}
	// uma decomposição gigante não pode explodir
	if got := validator.NormalizeUsername(strings.Repeat("é", 10000)); len(got) == 0 {
		t.Error("normalizou para vazio")
	}
}

func TestDB_Service_Register_StoresNormalizedUsername(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	svc := auth.NewService(repo, true)
	ctx := context.Background()
	u, err := svc.Register(ctx, uniqueEmail("nfc"), "  José  ", testPassword)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repo.DeleteUser(ctx, u.ID) })
	if u.Username != "José" {
		t.Errorf("username gravado = %+q, esperado NFC sem espaços", u.Username)
	}
}

// Mensagem do registro: a decisão (aceitável num servidor pessoal) é revelar "e-mail já cadastrado" com 409.
// O login, por outro lado, nunca distingue conta inexistente de senha errada.
func TestDB_Handler_Login_SameAnswerForUnknownEmailAndWrongPassword(t *testing.T) {
	h, repo, cleanup := setupTest(t, true)
	defer cleanup()
	u := registerUser(t, h, repo, "mesma-resposta")

	do := func(email string) []byte {
		rec := httptest.NewRecorder()
		h.Login(rec, protoRequest(t, http.MethodPost, "/auth/login/", &dto.LoginInput{Email: email, Password: "senha_errada_999"}))
		requireError(t, rec, http.StatusUnauthorized, "invalid_credentials")
		return rec.Body.Bytes()
	}
	if a, b := do(u.Email), do(uniqueEmail("fantasma")); string(a) != string(b) {
		t.Errorf("corpos diferentes revelam se a conta existe: %q vs %q", a, b)
	}
}
