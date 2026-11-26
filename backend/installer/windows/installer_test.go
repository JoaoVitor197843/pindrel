// Package installer_test checks the Windows installer and portable files from any platform: nothing here can run them
// (they need Windows), so what can break silently is pinned instead: the encodings Windows needs, and that every setting
// they write is one the server knows and accepts.
package installer_test

import (
	"bytes"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	"pindrel/internal/config"
)

var bom = []byte{0xef, 0xbb, 0xbf}

func read(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// Windows PowerShell 5.1 reads a script without a byte order mark as ANSI and Inno Setup does the same with its script:
// the accents of every message would come out garbled. cmd.exe reads its files in the OEM code page, so they stay ASCII,
// and with CRLF (labels and some commands misbehave with bare LF).
func TestEncodingsWindowsNeeds(t *testing.T) {
	for _, f := range []string{"pindrel-server.ps1", "pindrel-server.iss"} {
		if !bytes.HasPrefix(read(t, f), bom) {
			t.Errorf("%s must start with a UTF-8 byte order mark", f)
		}
	}
	for _, f := range []string{"portable/iniciar.cmd", "portable/parar.cmd"} {
		b := read(t, f)
		for i, c := range b {
			if c > 127 {
				t.Errorf("%s: byte %d is not ASCII", f, i)
				break
			}
		}
		if bytes.Count(b, []byte("\n")) != bytes.Count(b, []byte("\r\n")) {
			t.Errorf("%s must use CRLF line ends", f)
		}
	}
}

// knownKeys are the settings the server reads (every parseEnv of config.go) plus EMBEDDED_POSTGRES, which only the
// start script reads.
func knownKeys(t *testing.T) []string {
	t.Helper()
	src := string(read(t, "../../internal/config/config.go"))
	keys := []string{"EMBEDDED_POSTGRES"}
	for _, m := range regexp.MustCompile(`parseEnv\(c, "([A-Z_]+)"`).FindAllStringSubmatch(src, -1) {
		keys = append(keys, m[1])
	}
	if len(keys) < 20 {
		t.Fatalf("found only %d settings in config.go: the pattern no longer matches", len(keys))
	}
	return keys
}

// A key the server does not know is a setting that silently does nothing (a typo in the installer).
func TestEverySettingWrittenIsOneTheServerKnows(t *testing.T) {
	known := knownKeys(t)
	written := regexp.MustCompile(`'([A-Z][A-Z_]+)=`)
	for _, f := range []string{"pindrel-server.iss", "pindrel-server.ps1"} {
		matches := written.FindAllStringSubmatch(string(read(t, f)), -1)
		if len(matches) < 10 {
			t.Fatalf("%s: found only %d settings", f, len(matches))
		}
		for _, m := range matches {
			// the "open in the browser" shortcut (a .url file) is not a setting
			if m[1] != "URL" && !slices.Contains(known, m[1]) {
				t.Errorf("%s writes %s, which the server does not read", f, m[1])
			}
		}
	}
	for k := range config.ParseEnvFile(string(read(t, "server.env.example"))) {
		if !slices.Contains(known, k) {
			t.Errorf("server.env.example has %s, which the server does not read", k)
		}
	}
}

// withSettings loads a settings text into a clean environment (every known key unset first) and runs config.Load.
func withSettings(t *testing.T, text string) (*config.Config, error) {
	t.Helper()
	for _, k := range knownKeys(t) {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
	for k, v := range config.ParseEnvFile(text) {
		t.Setenv(k, v)
	}
	return config.Load()
}

// The example, with the two secrets filled in, is a configuration the server starts with.
func TestServerEnvExampleIsAccepted(t *testing.T) {
	text := string(read(t, "server.env.example")) + "\nJWT_SECRET=um-segredo\nDB_PASSWORD=senha\n"
	cfg, err := withSettings(t, text)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Database.Port != 5433 || cfg.Files.MinFreeBytes != 2<<30 {
		t.Errorf("unexpected values: %+v", cfg)
	}
}

// The settings a portable folder writes on its first run (New-PortableSettings), with the computed values put in, are a
// configuration the server starts with, and they keep the folder movable (no absolute path).
func TestPortableSettingsAreAccepted(t *testing.T) {
	src := string(read(t, "pindrel-server.ps1"))
	start := strings.Index(src, "function New-PortableSettings")
	end := strings.Index(src[start:], "[IO.File]::WriteAllLines")
	if start < 0 || end < 0 {
		t.Fatal("New-PortableSettings not found")
	}
	var lines []string
	for _, m := range regexp.MustCompile(`(?m)^\s*['"]([A-Z_]+=[^'"]*)['"],?\s*$`).FindAllStringSubmatch(src[start:start+end], -1) {
		lines = append(lines, regexp.MustCompile(`\$\([^)]*\)`).ReplaceAllString(m[1], "5433"))
	}
	text := strings.Join(lines, "\n")
	for _, want := range []string{"EMBEDDED_POSTGRES=true", "WEB_DIR=..\\public", "FILES_DIR=files", "DB_HOST=127.0.0.1"} {
		if !strings.Contains(text, want) {
			t.Errorf("portable settings lack %s:\n%s", want, text)
		}
	}
	if strings.Contains(text, ":\\") {
		t.Errorf("an absolute path would break a moved portable folder:\n%s", text)
	}
	if _, err := withSettings(t, text); err != nil {
		t.Fatalf("%v\n%s", err, text)
	}
}

// The start script follows the server long enough to see it give up on a database that never answers; otherwise the
// person is told nothing (the script already left). Pinned to database.Connect, whose numbers can change.
func TestStartFollowsLongerThanTheDatabaseWait(t *testing.T) {
	num := func(src, pattern string) int {
		t.Helper()
		m := regexp.MustCompile(pattern).FindStringSubmatch(src)
		if m == nil {
			t.Fatalf("pattern %q not found", pattern)
		}
		n, _ := strconv.Atoi(m[1])
		return n
	}
	pg := string(read(t, "../../internal/database/postgres.go"))
	attempts := num(pg, `Connect\(ctx, cfg, (\d+)\)`)
	ping := num(pg, `WithTimeout\(ctx, (\d+)\*time\.Second\)`)
	pause := num(pg, `time\.After\((\d+) \* time\.Second\)`)
	worst := (attempts*ping + (attempts-1)*pause) * 1000
	follow := num(string(read(t, "pindrel-server.ps1")), `WaitForExit\((\d+)\)\) \{ return 0 \}`)
	if follow < worst+5000 {
		t.Fatalf("the script follows the server for %d ms, but its database wait can take %d ms", follow, worst)
	}
}

// With an accent in the folder of the programs, initdb cannot make a UTF8 cluster (it writes that path into an SQL
// command in the ANSI code page), so the cluster may be WIN125x. The Pindrel database itself must still be UTF8 and C,
// which only a createdb from template0 with both given can promise.
func TestPindrelDatabaseIsAlwaysUTF8(t *testing.T) {
	src := string(read(t, "pindrel-server.ps1"))
	createdb := regexp.MustCompile(`createdb\.exe'\) @\(([^)]*)\)`).FindStringSubmatch(src)
	if createdb == nil {
		t.Fatal("createdb call not found")
	}
	for _, want := range []string{`'-E', 'UTF8'`, `'-T', 'template0'`, `'--locale=C'`} {
		if !strings.Contains(createdb[1], want) {
			t.Errorf("createdb lacks %s: %s", want, createdb[1])
		}
	}
	if !strings.Contains(src, `'-E', $encoding`) || !strings.Contains(src, "function Get-ClusterEncoding") {
		t.Error("initdb no longer takes the encoding that suits the folder of the programs")
	}
}
