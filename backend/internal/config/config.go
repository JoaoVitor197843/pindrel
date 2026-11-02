package config

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"pindrel/internal/clientip"
)

type SSLMode string

const (
	SSLDisable    SSLMode = "disable"
	SSLAllow      SSLMode = "allow"
	SSLPrefer     SSLMode = "prefer"
	SSLRequire    SSLMode = "require"
	SSLVerifyCA   SSLMode = "verify-ca"
	SSLVerifyFull SSLMode = "verify-full"
)

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	DBName   string
	SSLMode  SSLMode
	MaxConns int
}

type Config struct {
	Port                string
	ServerName          string
	Database            DatabaseConfig
	JWTSecret           string
	JWTAccessExpiry     time.Duration
	JWTRefreshExpiry    time.Duration
	RegistrationEnabled bool
	DebugMode           bool
	// InAppRateLimit: per-instance in-memory rate limits. Turn it off behind a load balancer that limits instead.
	InAppRateLimit bool
	// ClientKey says which client a request belongs to, for the in-app rate limits: the connection's address, or,
	// behind a proxy listed in TRUSTED_PROXIES, the client that proxy vouches for in CLIENT_IP_HEADER. nil = the
	// connection's address.
	ClientKey func(*http.Request) string
}

func ptr[T any](v T) *T {
	return &v
}

type errCollector struct {
	errs []error
}

func parseEnv[T any](c *errCollector, key string, fallback *T, parser func(string) (T, error)) T {
	val, exists := os.LookupEnv(key)
	val = strings.TrimSpace(val)
	if !exists || val == "" {
		if fallback == nil {
			var zero T
			c.errs = append(c.errs, fmt.Errorf("variável obrigatória ausente: %s", key))
			return zero
		}
		return *fallback
	}
	parsed, err := parser(val)
	if err != nil {
		var zero T
		c.errs = append(c.errs, fmt.Errorf("variável %s contém valor inválido ('%s'): %w", key, val, err))
		return zero
	}
	return parsed
}

func parseString(s string) (string, error) {
	return s, nil
}

func parseSSLMode(val string) (SSLMode, error) {
	mode := SSLMode(strings.ToLower(strings.TrimSpace(val)))

	switch mode {
	case SSLDisable, SSLAllow, SSLPrefer, SSLRequire, SSLVerifyCA, SSLVerifyFull:
		return mode, nil
	default:
		return "", fmt.Errorf(
			"invalid SSL mode '%s'. permitted options: [disable, allow, prefer, require, verify-ca, verify-full]",
			val,
		)
	}
}

func parsePortRange(min, max int) func(string) (int, error) {
	return func(val string) (int, error) {
		port, err := strconv.Atoi(val)
		if err != nil {
			return 0, fmt.Errorf("this is not a valid integer: %w", err)
		}
		if port < min || port > max {
			return 0, fmt.Errorf("port %d out of range [%d-%d]", port, min, max)
		}
		return port, nil
	}
}
func Load() (*Config, error) {
	c := &errCollector{}
	port := parseEnv(c, "PORT", nil, parsePortRange(1024, 65535))
	dbHost := parseEnv(c, "DB_HOST", nil, parseString)
	dbPort := parseEnv(c, "DB_PORT", nil, parsePortRange(1, 65535))
	dbUser := parseEnv(c, "DB_USER", nil, parseString)
	dbPassword := parseEnv(c, "DB_PASSWORD", nil, parseString)
	dbName := parseEnv(c, "DB_NAME", nil, parseString)
	sslMode := parseEnv(c, "SSL_MODE", nil, parseSSLMode)
	jwtSecret := parseEnv(c, "JWT_SECRET", nil, parseString)
	jwtAccessExpiry := parseEnv(c, "JWT_ACCESS_EXPIRY", nil, time.ParseDuration)
	jwtRefreshExpiry := parseEnv(c, "JWT_REFRESH_EXPIRY", nil, time.ParseDuration)
	serverName := parseEnv(c, "SERVER_NAME", ptr("Pindrel"), parseString)
	registrationEnabled := parseEnv(c, "REGISTRATION_ENABLED", ptr(true), strconv.ParseBool)
	inAppRateLimit := parseEnv(c, "IN_APP_RATE_LIMIT", ptr(true), strconv.ParseBool)
	dbMaxConns := parseEnv(c, "DB_MAX_CONNS", ptr(4), parsePortRange(1, 100))
	debugMode := parseEnv(c, "DEBUG_MODE", ptr(false), strconv.ParseBool)
	trustedProxies := parseEnv(c, "TRUSTED_PROXIES", ptr([]net.IPNet(nil)), clientip.ParseTrusted)
	clientIPHeader := parseEnv(c, "CLIENT_IP_HEADER", ptr("X-Forwarded-For"), parseString)
	var clientKey func(*http.Request) string
	if resolver, err := clientip.New(trustedProxies, clientIPHeader); err != nil {
		c.errs = append(c.errs, fmt.Errorf("variável CLIENT_IP_HEADER contém valor inválido ('%s'): %w", clientIPHeader, err))
	} else {
		clientKey = resolver.Key
	}
	if len(c.errs) > 0 {
		return nil, fmt.Errorf("erros de configuração no ambiente:\n - %w", errors.Join(c.errs...))
	}
	return &Config{
		Port: fmt.Sprintf(":%d", port),
		Database: DatabaseConfig{
			Host:     dbHost,
			Port:     dbPort,
			User:     dbUser,
			Password: dbPassword,
			DBName:   dbName,
			SSLMode:  sslMode,
			MaxConns: dbMaxConns,
		},
		ServerName:          serverName,
		JWTSecret:           jwtSecret,
		JWTAccessExpiry:     jwtAccessExpiry,
		JWTRefreshExpiry:    jwtRefreshExpiry,
		RegistrationEnabled: registrationEnabled,
		DebugMode:           debugMode,
		InAppRateLimit:      inAppRateLimit,
		ClientKey:           clientKey,
	}, nil
}
