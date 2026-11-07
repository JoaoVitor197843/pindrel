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
	// Files: where uploaded files live and how much of it one person or one file may take. An empty FilesDir turns the
	// feature off (no routes, no disk use).
	Files FilesConfig
}

// FilesConfig holds the limits of internal/files. Sizes are in bytes.
type FilesConfig struct {
	Dir            string
	MaxFileBytes   int64
	QuotaBytes     int64
	MinFreeBytes   int64
	MaxOpenUploads int
	UploadTTL      time.Duration
	OrphanGrace    time.Duration
	LinkTTL        time.Duration
	// ChunksPerMinute limits the pieces one person may send (the global per-IP limit does not apply to them).
	ChunksPerMinute int
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

// parseBytes reads a size in bytes (a plain integer) within [min, max].
func parseBytes(min, max int64) func(string) (int64, error) {
	return func(val string) (int64, error) {
		n, err := strconv.ParseInt(val, 10, 64)
		if err != nil {
			return 0, fmt.Errorf("this is not a valid integer: %w", err)
		}
		if n < min || n > max {
			return 0, fmt.Errorf("%d out of range [%d-%d]", n, min, max)
		}
		return n, nil
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
	filesDir := parseEnv(c, "FILES_DIR", ptr(""), parseString)
	filesMax := parseEnv(c, "FILE_MAX_BYTES", ptr(int64(1<<30)), parseBytes(1<<20, 64<<30))
	filesQuota := parseEnv(c, "FILE_QUOTA_BYTES", ptr(int64(20<<30)), parseBytes(1<<20, 100<<40))
	filesMinFree := parseEnv(c, "FILES_MIN_FREE_BYTES", ptr(int64(20<<30)), parseBytes(0, 100<<40))
	filesOpen := parseEnv(c, "FILE_UPLOADS_MAX_OPEN", ptr(4), parsePortRange(1, 100))
	filesUploadTTL := parseEnv(c, "FILE_UPLOAD_TTL", ptr(24*time.Hour), time.ParseDuration)
	filesOrphanGrace := parseEnv(c, "FILE_ORPHAN_GRACE", ptr(7*24*time.Hour), time.ParseDuration)
	filesLinkTTL := parseEnv(c, "FILE_LINK_TTL", ptr(10*time.Minute), time.ParseDuration)
	filesChunks := parseEnv(c, "FILE_CHUNKS_PER_MIN", ptr(600), parsePortRange(1, 100000))
	clientIPHeader := parseEnv(c, "CLIENT_IP_HEADER", ptr("X-Forwarded-For"), parseString)
	var clientKey func(*http.Request) string
	if resolver, err := clientip.New(trustedProxies, clientIPHeader); err != nil {
		c.errs = append(c.errs, fmt.Errorf("variável CLIENT_IP_HEADER contém valor inválido ('%s'): %w", clientIPHeader, err))
	} else {
		clientKey = resolver.Key
	}
	// the file clean-up holds one connection (its lock) while it works with another
	if filesDir != "" && dbMaxConns < 2 {
		c.errs = append(c.errs, errors.New("DB_MAX_CONNS precisa ser pelo menos 2 quando FILES_DIR está definido"))
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
		Files: FilesConfig{
			Dir: filesDir, MaxFileBytes: filesMax, QuotaBytes: filesQuota, MinFreeBytes: filesMinFree, MaxOpenUploads: filesOpen,
			UploadTTL: filesUploadTTL, OrphanGrace: filesOrphanGrace, LinkTTL: filesLinkTTL, ChunksPerMinute: filesChunks,
		},
	}, nil
}
