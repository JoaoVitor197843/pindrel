package config_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"pindrel/internal/config"
)

// The same lines as the gateway's settings file (gateway/src/envfile.rs), so one installer writes both.
func TestParseEnvFile_PairsCommentsQuotesAndExport(t *testing.T) {
	got := config.ParseEnvFile("\xef\xbb\xbf# comentário\r\nPORT=8080\r\n\r\n  export SERVER_NAME = \"Casa do João\"  \nDB_PASSWORD='a$b#c'\nJWT_SECRET=x=y\nlinha sem igual\n1BAD=x\nBAD-KEY=x\n=semchave\nPORT=9000\nVAZIO=\n")
	want := map[string]string{"PORT": "9000", "SERVER_NAME": "Casa do João", "DB_PASSWORD": "a$b#c", "JWT_SECRET": "x=y", "VAZIO": ""}
	if len(got) != len(want) {
		t.Errorf("got %v, want %v", got, want)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

// Nothing is expanded: a generated password with $ stays what it is (godotenv would have read "$b" as a variable).
func TestParseEnvFile_ExpandsNothing(t *testing.T) {
	t.Setenv("HOME", "/root")
	got := config.ParseEnvFile("A=$HOME\nB=\"${HOME}\"\nC=`id`\n")
	if got["A"] != "$HOME" || got["B"] != "${HOME}" || got["C"] != "`id`" {
		t.Errorf("expanded: %v", got)
	}
}

func TestParseEnvFile_NeverPanicsOnJunk(t *testing.T) {
	for _, s := range []string{"", "=", "\x00\x00=\x00", strings.Repeat("A=", 10000), "\"", "A=\"", "A='", "export", "export =x", "\xff\xfe=1"} {
		_ = config.ParseEnvFile(s)
	}
}

func TestLoadEnvFile_TheRealEnvironmentWins(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "server.env")
	if err := os.WriteFile(file, []byte("PINDREL_T_A=do-arquivo\nPINDREL_T_B=do-arquivo\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PINDREL_T_A", "da-mao")
	t.Setenv("PINDREL_T_B", "")
	os.Unsetenv("PINDREL_T_B")
	if err := config.LoadEnvFile(file); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("PINDREL_T_A") != "da-mao" || os.Getenv("PINDREL_T_B") != "do-arquivo" {
		t.Errorf("A=%q B=%q", os.Getenv("PINDREL_T_A"), os.Getenv("PINDREL_T_B"))
	}
}

func TestLoadEnvFile_MissingOrHugeIsAnError(t *testing.T) {
	dir := t.TempDir()
	if err := config.LoadEnvFile(filepath.Join(dir, "nao-existe.env")); err == nil {
		t.Error("a missing file was accepted")
	}
	huge := filepath.Join(dir, "huge.env")
	if err := os.WriteFile(huge, []byte(strings.Repeat("# x\n", 20000)), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := config.LoadEnvFile(huge); err == nil || !strings.Contains(err.Error(), "grande demais") {
		t.Errorf("a 80 KiB file: %v", err)
	}
	if err := config.LoadEnvFile(dir); err == nil {
		t.Error("a folder was read as a settings file")
	}
}

func TestEnvFilePath(t *testing.T) {
	env := func(v string) func(string) string { return func(string) string { return v } }
	for _, c := range []struct {
		args []string
		env  string
		want string
		err  bool
	}{
		{nil, "", "", false},
		{nil, "  C:\\dados\\server.env ", "C:\\dados\\server.env", false},
		{[]string{"--config", "a.env"}, "b.env", "a.env", false},
		{[]string{"--config=a.env"}, "", "a.env", false},
		{[]string{"--check", "--config", "a.env"}, "", "a.env", false},
		{[]string{"--config"}, "b.env", "", true},
		{[]string{"--config", ""}, "", "", true},
		{[]string{"--config="}, "", "", true},
	} {
		got, err := config.EnvFilePath(c.args, env(c.env))
		if got != c.want || (err != nil) != c.err {
			t.Errorf("%v env=%q: %q %v", c.args, c.env, got, err)
		}
	}
}
