package config

import "os"

type Config struct {
	ListenAddr         string
	DatabaseURL        string
	RuntimePath        string
	RedisURL           string
	JWTSecret          string
	AuthDisabled       bool
	AdminUser          string
	AdminPassword      string
	EngineReloadURL    string
	EngineAdminToken   string
	MaxMindLicenseKey  string
	GeoIPDataPath      string
	GeoIPSyncInterval  string
	BotsDataPath       string
	BotSyncInterval    string
	CertsPath          string
	ACMEDefaultEmail   string
	ACMEStaging        bool
	CertRenewInterval  string
	HaproxyReloadCmd   string
}

func Load() Config {
	return Config{
		ListenAddr:       env("BADSECTOR_API_ADDR", ":8080"),
		DatabaseURL:      env("BADSECTOR_DATABASE_URL", "sqlite://./data/badsector.db"),
		RuntimePath:      env("BADSECTOR_RUNTIME", "./runtime"),
		RedisURL:         env("BADSECTOR_REDIS_URL", "redis://localhost:6379"),
		JWTSecret:        env("BADSECTOR_JWT_SECRET", "badsector-dev-secret-change-me"),
		AuthDisabled:     env("BADSECTOR_AUTH_DISABLED", "false") == "true",
		AdminUser:        env("BADSECTOR_ADMIN_USER", "admin"),
		AdminPassword:    env("BADSECTOR_ADMIN_PASSWORD", "badsector"),
		EngineReloadURL:  env("BADSECTOR_ENGINE_RELOAD_URL", ""),
		EngineAdminToken: env("BADSECTOR_ENGINE_ADMIN_TOKEN", "badsector-engine-token"),
		MaxMindLicenseKey:  env("MAXMIND_LICENSE_KEY", ""),
		GeoIPDataPath:      env("BADSECTOR_GEOIP_PATH", "./data/geoip"),
		GeoIPSyncInterval:  env("BADSECTOR_GEOIP_SYNC_INTERVAL", "24h"),
		BotsDataPath:       env("BADSECTOR_BOTS_PATH", "./data/bots"),
		BotSyncInterval:    env("BADSECTOR_BOT_SYNC_INTERVAL", "24h"),
		CertsPath:          env("BADSECTOR_CERTS_PATH", "./data/certs"),
		ACMEDefaultEmail:   env("BADSECTOR_ACME_EMAIL", ""),
		ACMEStaging:        env("BADSECTOR_ACME_STAGING", "false") == "true",
		CertRenewInterval:  env("BADSECTOR_CERT_RENEW_INTERVAL", "6h"),
		HaproxyReloadCmd:   env("BADSECTOR_HAPROXY_RELOAD_CMD", ""),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
