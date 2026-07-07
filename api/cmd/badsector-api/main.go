package main

import (
	"log"
	"net/http"

	"github.com/badsector/badsector/api/internal/auth"
	"github.com/badsector/badsector/api/internal/certs"
	"github.com/badsector/badsector/api/internal/config"
	"github.com/badsector/badsector/api/internal/db"
	"github.com/badsector/badsector/api/internal/handler"
	"github.com/badsector/badsector/api/internal/metrics"
	"github.com/badsector/badsector/api/internal/runtime"
	"github.com/badsector/badsector/api/internal/trace"
	"github.com/joho/godotenv"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

func main() {
	_ = godotenv.Load()

	cfg := config.Load()
	database, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}

	if err := db.Migrate(database); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	if err := db.SeedDefault(database); err != nil {
		log.Fatalf("seed: %v", err)
	}

	generator := runtime.NewGenerator(cfg.RuntimePath)
	reloader := runtime.NewEngineReloader(cfg.EngineReloadURL, cfg.EngineAdminToken)
	authService := auth.NewService(cfg.JWTSecret, cfg.AuthDisabled, cfg.AdminUser, cfg.AdminPassword)

	traceStore, err := trace.NewStore(cfg.RedisURL)
	if err != nil {
		log.Fatalf("redis trace store: %v", err)
	}

	metricsStore, err := metrics.NewStore(cfg.RedisURL)
	if err != nil {
		log.Fatalf("redis metrics store: %v", err)
	}

	certManager, err := certs.NewManager(
		database,
		cfg.RedisURL,
		cfg.CertsPath,
		cfg.ACMEDefaultEmail,
		cfg.ACMEStaging,
		cfg.HaproxyReloadCmd,
	)
	if err != nil {
		log.Fatalf("cert manager: %v", err)
	}

	h := handler.New(database, generator, reloader, traceStore, metricsStore, authService, certManager)

	e := echo.New()
	e.HideBanner = true
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	e.Use(middleware.CORS())

	e.GET("/health", func(c echo.Context) error {
		return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
	})

	v1 := e.Group("/api/v1")
	v1.Use(authService.Middleware())
	h.Register(v1)

	addr := cfg.ListenAddr
	if addr == "" {
		addr = ":8080"
	}

	if err := generator.GenerateAll(database); err != nil {
		log.Printf("warning: initial runtime generate: %v", err)
	} else if err := reloader.Reload(); err != nil {
		log.Printf("warning: initial engine reload: %v", err)
	}

	if cfg.AuthDisabled {
		log.Printf("warning: API authentication is disabled (BADSECTOR_AUTH_DISABLED=true)")
	}

	log.Printf("badsector-api listening on %s", addr)
	if err := e.Start(addr); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
