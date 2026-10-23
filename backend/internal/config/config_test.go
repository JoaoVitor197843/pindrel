package config_test

import (
	"testing"

	"plany/internal/config"
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
	if cfg.ServerName != "Plany" || !cfg.InAppRateLimit || cfg.Database.MaxConns != 4 {
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
