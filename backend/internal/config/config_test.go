package config_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pindrel/internal/config"
)

func setRequired(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{
		"PORT": "8080", "DB_HOST": "h", "DB_PORT": "5432", "DB_USER": "u", "DB_PASSWORD": "p",
		"DB_NAME": "n", "SSL_MODE": "disable", "JWT_SECRET": "s", "JWT_ACCESS_EXPIRY": "15m", "JWT_REFRESH_EXPIRY": "1h",
	} {
		t.Setenv(k, v)
	}
}

func TestLoad_Defaults(t *testing.T) {
	setRequired(t)
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ServerName != "Pindrel" || !cfg.InAppRateLimit || cfg.Database.MaxConns != 4 {
		t.Errorf("unexpected defaults: %+v", cfg)
	}
}

func TestLoad_LoadBalancerSettings(t *testing.T) {
	setRequired(t)
	t.Setenv("SERVER_NAME", "Casa")
	t.Setenv("IN_APP_RATE_LIMIT", "false")
	t.Setenv("DB_MAX_CONNS", "2")
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ServerName != "Casa" || cfg.InAppRateLimit || cfg.Database.MaxConns != 2 {
		t.Errorf("unexpected config: %+v", cfg)
	}
}

func TestLoad_InvalidMaxConns(t *testing.T) {
	setRequired(t)
	t.Setenv("DB_MAX_CONNS", "0")
	if _, err := config.Load(); err == nil {
		t.Fatal("expected an error for DB_MAX_CONNS=0")
	}
}

func TestLoad_ClientIPDefaultsToTheConnection(t *testing.T) {
	setRequired(t)
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ClientKey == nil {
		t.Fatal("ClientKey must always be set")
	}
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "203.0.113.5:80"
	req.Header.Set("X-Forwarded-For", "9.9.9.9")
	if got := cfg.ClientKey(req); got != "203.0.113.5" {
		t.Errorf("no trusted proxy: key = %q, want the connection's address", got)
	}
}

func TestLoad_TrustedProxiesAndHeader(t *testing.T) {
	setRequired(t)
	t.Setenv("TRUSTED_PROXIES", "127.0.0.1, ::1")
	t.Setenv("CLIENT_IP_HEADER", "CF-Connecting-IP")
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "127.0.0.1:80"
	req.Header.Set("Cf-Connecting-Ip", "198.51.100.7")
	req.Header.Set("X-Forwarded-For", "9.9.9.9")
	if got := cfg.ClientKey(req); got != "198.51.100.7" {
		t.Errorf("key = %q, want the Cloudflare header's address", got)
	}
}

func TestLoad_BadProxySettingsAreReportedTogether(t *testing.T) {
	setRequired(t)
	t.Setenv("TRUSTED_PROXIES", "127.0.0.1, banana")
	t.Setenv("CLIENT_IP_HEADER", "not a header")
	t.Setenv("DB_MAX_CONNS", "0")
	_, err := config.Load()
	if err == nil {
		t.Fatal("expected errors")
	}
	for _, want := range []string{"TRUSTED_PROXIES", "CLIENT_IP_HEADER", "DB_MAX_CONNS"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error does not mention %s: %v", want, err)
		}
	}
}

func TestLoad_FilesAreOffByDefaultAndTheLimitsHaveSaneDefaults(t *testing.T) {
	setRequired(t)
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	f := cfg.Files
	if f.Dir != "" || f.MaxFileBytes != 1<<30 || f.QuotaBytes != 20<<30 || f.MinFreeBytes != 20<<30 || f.MaxOpenUploads != 4 || f.ChunksPerMinute != 600 {
		t.Errorf("defaults: %+v", f)
	}
}

func TestLoad_FilesSettings(t *testing.T) {
	setRequired(t)
	t.Setenv("FILES_DIR", "/data/files")
	t.Setenv("FILE_MAX_BYTES", "5242880")
	t.Setenv("FILE_QUOTA_BYTES", "104857600")
	t.Setenv("FILES_MIN_FREE_BYTES", "0")
	t.Setenv("FILE_UPLOAD_TTL", "2h")
	t.Setenv("FILE_ORPHAN_GRACE", "24h")
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	f := cfg.Files
	if f.Dir != "/data/files" || f.MaxFileBytes != 5<<20 || f.QuotaBytes != 100<<20 || f.MinFreeBytes != 0 || f.UploadTTL.Hours() != 2 || f.OrphanGrace.Hours() != 24 {
		t.Errorf("settings: %+v", f)
	}
}

func TestLoad_FilesSettingsOutOfRangeOrBrokenAreRefusedTogether(t *testing.T) {
	for name, env := range map[string][2]string{
		"zero max":        {"FILE_MAX_BYTES", "0"},
		"negative quota":  {"FILE_QUOTA_BYTES", "-1"},
		"not a number":    {"FILE_MAX_BYTES", "muito"},
		"free below zero": {"FILES_MIN_FREE_BYTES", "-5"},
		"open uploads 0":  {"FILE_UPLOADS_MAX_OPEN", "0"},
		"bad duration":    {"FILE_LINK_TTL", "dez minutos"},
		"chunks 0":        {"FILE_CHUNKS_PER_MIN", "0"},
	} {
		setRequired(t)
		t.Setenv(env[0], env[1])
		if _, err := config.Load(); err == nil {
			t.Errorf("%s: accepted %s=%s", name, env[0], env[1])
		}
	}
}

func TestLoad_FilesNeedTwoDatabaseConnections(t *testing.T) {
	setRequired(t)
	t.Setenv("FILES_DIR", "/data/files")
	t.Setenv("DB_MAX_CONNS", "1")
	if _, err := config.Load(); err == nil || !strings.Contains(err.Error(), "DB_MAX_CONNS") {
		t.Errorf("one connection with files on: %v", err)
	}
	t.Setenv("FILES_DIR", "")
	if _, err := config.Load(); err != nil {
		t.Errorf("one connection with files off: %v", err)
	}
}
