package auth_test

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"runtime"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"plany/internal/api/dto"
	"plany/internal/auth"
)

func resetArgon(t *testing.T) {
	t.Cleanup(func() { auth.SetArgonLimits(2, 5*time.Second) })
}

// RAM stress: a flood of simultaneous password checks must not multiply the ~19 MiB of Argon2 memory.
// Measured before the cap: 16 concurrent -> 330 MiB RSS, 64 -> 1 GiB (the budget is 512 MB, 256 recommended).
func TestArgon_ConcurrentFloodStaysInsideRAMBudget(t *testing.T) {
	resetArgon(t)
	auth.SetArgonLimits(2, time.Minute) // nobody gives up: every request must still finish
	hash, err := auth.HashPassword("xK9#mQ2$vL")
	if err != nil {
		t.Fatal(err)
	}

	runtime.GC()
	var base runtime.MemStats
	runtime.ReadMemStats(&base)

	var peak atomic.Uint64
	stop := make(chan struct{})
	sampled := make(chan struct{})
	go func() {
		defer close(sampled)
		var m runtime.MemStats
		for {
			select {
			case <-stop:
				return
			case <-time.After(2 * time.Millisecond):
				runtime.ReadMemStats(&m)
				if m.HeapInuse > peak.Load() {
					peak.Store(m.HeapInuse)
				}
			}
		}
	}()

	var wg sync.WaitGroup
	var wrong atomic.Int32
	for i := 0; i < 64; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if ok, err := auth.VerifyPassword(hash, "errada_errada"); ok || err != nil {
				wrong.Add(1)
			}
		}()
	}
	wg.Wait()
	close(stop)
	<-sampled

	if wrong.Load() != 0 {
		t.Fatalf("%d verifications gave the wrong answer or an error", wrong.Load())
	}
	grown := int64(peak.Load()) - int64(base.HeapInuse)
	const budget = 100 << 20 // 2 slots * ~19 MiB + slack; unbounded would be ~1.2 GiB
	if grown > budget {
		t.Fatalf("heap grew %d MiB during 64 concurrent verifications, want <= %d MiB", grown>>20, budget>>20)
	}
}

// When the slots stay busy past the wait, callers get ErrServerBusy instead of piling up memory,
// nobody panics, and the system works again afterwards.
func TestArgon_BusyReturnsErrServerBusyAndRecovers(t *testing.T) {
	resetArgon(t)
	hash, _ := auth.HashPassword("xK9#mQ2$vL")
	auth.SetArgonLimits(1, time.Millisecond)

	var wg sync.WaitGroup
	var busy, done atomic.Int32
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := auth.VerifyPassword(hash, "errada_errada")
			switch {
			case errors.Is(err, auth.ErrServerBusy):
				busy.Add(1)
			case err == nil:
				done.Add(1)
			default:
				t.Errorf("unexpected error: %v", err)
			}
		}()
	}
	wg.Wait()
	if busy.Load() == 0 || done.Load() == 0 {
		t.Fatalf("busy=%d done=%d: expected both some rejections and some completions", busy.Load(), done.Load())
	}

	auth.SetArgonLimits(1, 10*time.Second)
	if ok, err := auth.VerifyPassword(hash, "xK9#mQ2$vL"); !ok || err != nil {
		t.Fatalf("did not recover: ok=%v err=%v", ok, err)
	}
}

// A slot is always returned, even when the hash is malformed or the password is huge.
func TestArgon_SlotsAreReleasedAfterErrors(t *testing.T) {
	resetArgon(t)
	auth.SetArgonLimits(1, 200*time.Millisecond)
	for i := 0; i < 20; i++ {
		auth.VerifyPassword("lixo", "x")
		auth.HashPassword("curta")
	}
	hash, err := auth.HashPassword("xK9#mQ2$vL")
	if err != nil {
		t.Fatalf("slot leaked: %v", err)
	}
	if ok, err := auth.VerifyPassword(hash, "xK9#mQ2$vL"); !ok || err != nil {
		t.Fatalf("slot leaked: ok=%v err=%v", ok, err)
	}
}

// Over HTTP: a login flood against a busy server answers 401 or 503, never 500, and sets Retry-After.
func TestHandler_Login_FloodAnswers503NotOOMOr500(t *testing.T) {
	resetArgon(t)
	h, repo, cleanup := setupTest(t, true)
	defer cleanup()
	u := registerUser(t, h, repo, "flood-503")
	auth.SetArgonLimits(1, time.Millisecond)

	const n = 16
	recs := make([]*httptest.ResponseRecorder, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			recs[i] = httptest.NewRecorder()
			h.Login(recs[i], protoRequest(t, http.MethodPost, "/auth/login/", &dto.LoginInput{Email: u.Email, Password: "senha_errada_999"}))
		}(i)
	}
	wg.Wait()

	var busy int
	for _, rec := range recs {
		switch rec.Code {
		case http.StatusUnauthorized:
		case http.StatusServiceUnavailable:
			busy++
			requireError(t, rec, http.StatusServiceUnavailable, "server_busy")
			if rec.Header().Get("Retry-After") == "" {
				t.Error("503 without Retry-After")
			}
		default:
			t.Errorf("status %d: only 401 or 503 are acceptable", rec.Code)
		}
	}
	if busy == 0 {
		t.Error("no request was turned away: the cap is not in effect")
	}
}
