package config

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"
)

// maxEnvFileBytes: a settings file is a few lines; anything bigger is not one.
const maxEnvFileBytes = 64 << 10

// ParseEnvFile reads `KEY=VALUE` lines with the same rules as the gateway's settings file (gateway/src/envfile.rs), so one
// installer can write both: blank lines and lines starting with # are skipped, `export ` before a key and one pair of
// matching quotes around a value are accepted, and NOTHING is expanded (godotenv would turn a `$` inside a generated
// password into an empty variable). A line that is not a setting is ignored; the last line for a key wins.
func ParseEnvFile(text string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(strings.TrimPrefix(text, "\xef\xbb\xbf"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if rest, ok := strings.CutPrefix(line, "export "); ok {
			line = strings.TrimSpace(rest)
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if !validKey(key) {
			continue
		}
		out[key] = unquote(strings.TrimSpace(value))
	}
	return out
}

func validKey(k string) bool {
	if k == "" {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
		letter := c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_'
		if !letter && (i == 0 || c < '0' || c > '9') {
			return false
		}
	}
	return true
}

func unquote(v string) string {
	for _, q := range []byte{'"', '\''} {
		if len(v) >= 2 && v[0] == q && v[len(v)-1] == q {
			return v[1 : len(v)-1]
		}
	}
	return v
}

// LoadEnvFile reads a settings file and sets every variable that the real environment does not already have: a variable
// set by hand still overrides what the installer wrote.
func LoadEnvFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("não foi possível ler %s: %w", path, err)
	}
	defer f.Close()
	if info, err := f.Stat(); err == nil && info.IsDir() {
		return fmt.Errorf("%s é uma pasta, não um arquivo de configuração", path)
	}
	raw, err := io.ReadAll(io.LimitReader(f, maxEnvFileBytes+1))
	if err != nil {
		return fmt.Errorf("não foi possível ler %s: %w", path, err)
	}
	if len(raw) > maxEnvFileBytes {
		return fmt.Errorf("%s é grande demais para um arquivo de configuração (mais de %d KiB)", path, maxEnvFileBytes>>10)
	}
	for k, v := range ParseEnvFile(string(bytes.ToValidUTF8(raw, []byte("�")))) {
		if _, set := os.LookupEnv(k); !set {
			if err := os.Setenv(k, v); err != nil {
				return fmt.Errorf("%s: %w", k, err)
			}
		}
	}
	return nil
}

// EnvFilePath says which settings file to read: `--config <file>` (or `--config=<file>`) first, then PINDREL_CONFIG; ""
// when neither is given. A `--config` without a file is an error: starting on settings the operator did not mean is
// worse than not starting.
func EnvFilePath(args []string, getenv func(string) string) (string, error) {
	for i, a := range args {
		if a == "--config" {
			if i+1 >= len(args) || args[i+1] == "" {
				return "", fmt.Errorf("--config precisa do caminho de um arquivo de configuração")
			}
			return args[i+1], nil
		}
		if v, ok := strings.CutPrefix(a, "--config="); ok {
			if v == "" {
				return "", fmt.Errorf("--config precisa do caminho de um arquivo de configuração")
			}
			return v, nil
		}
	}
	return strings.TrimSpace(getenv("PINDREL_CONFIG")), nil
}
