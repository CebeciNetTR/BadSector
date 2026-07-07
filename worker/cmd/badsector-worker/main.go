package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/badsector/badsector/internal/certs"
	"github.com/badsector/badsector/internal/config"
	"github.com/badsector/badsector/internal/db"
	"github.com/badsector/badsector/internal/geoip"
	"github.com/badsector/badsector/internal/runtime"
)

func main() {
	cfg := config.Load()
	database, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}

	generator := runtime.NewGenerator(cfg.RuntimePath)
	reloader := runtime.NewEngineReloader(cfg.EngineReloadURL, cfg.EngineAdminToken)
	geoSyncer := geoip.NewSyncer(cfg.MaxMindLicenseKey, cfg.GeoIPDataPath)

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

	syncInterval, err := time.ParseDuration(cfg.GeoIPSyncInterval)
	if err != nil {
		syncInterval = 24 * time.Hour
	}

	certRenewInterval, err := time.ParseDuration(cfg.CertRenewInterval)
	if err != nil {
		certRenewInterval = 6 * time.Hour
	}

	log.Printf("badsector-worker started (geoip=%s certs=%s)", cfg.GeoIPDataPath, cfg.CertsPath)

	runGeoSync(geoSyncer, reloader)
	lastGeoSync := time.Now()
	lastCertRenew := time.Now()

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		if err := generator.GenerateAndReload(database, reloader); err != nil {
			log.Printf("generate runtime: %v", err)
		}

		if time.Since(lastGeoSync) >= syncInterval {
			runGeoSync(geoSyncer, reloader)
			lastGeoSync = time.Now()
		}

		if time.Since(lastCertRenew) >= certRenewInterval {
			runCertRenew(certManager)
			lastCertRenew = time.Now()
		}

		select {
		case <-ticker.C:
		case <-exitSignal():
			return
		}
	}
}

func runCertRenew(manager *certs.Manager) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	n, err := manager.RenewDue(ctx)
	if err != nil {
		log.Printf("cert renew: %v", err)
		return
	}
	if n > 0 {
		log.Printf("cert renew: renewed %d certificate(s)", n)
	}
}

func runGeoSync(syncer *geoip.Syncer, reloader *runtime.EngineReloader) {
	if syncer.LicenseKey == "" {
		st := syncer.Status()
		if !st.CountryOK {
			log.Printf("geoip: MAXMIND_LICENSE_KEY not set; Country MMDB missing at %s", st.CountryPath)
		}
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	if err := syncer.Sync(ctx); err != nil {
		log.Printf("geoip sync: %v", err)
		return
	}

	st := syncer.Status()
	log.Printf("geoip sync ok: country=%v asn=%v", st.CountryOK, st.ASNOK)

	if reloader != nil {
		if err := reloader.Reload(); err != nil {
			log.Printf("geoip sync engine reload: %v", err)
		}
	}
}

func exitSignal() <-chan os.Signal {
	ch := make(chan os.Signal)
	return ch
}
