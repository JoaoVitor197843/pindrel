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
