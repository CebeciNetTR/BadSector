package geoip

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	editionCountry = "GeoLite2-Country"
	editionASN     = "GeoLite2-ASN"
)

type Syncer struct {
	LicenseKey string
	DataDir    string
	Client     *http.Client
}

func NewSyncer(licenseKey, dataDir string) *Syncer {
	return &Syncer{
		LicenseKey: licenseKey,
		DataDir:    dataDir,
		Client: &http.Client{
			Timeout: 5 * time.Minute,
		},
	}
}

type Status struct {
	CountryPath string `json:"country_path"`
	ASNPath     string `json:"asn_path"`
	CountryOK   bool   `json:"country_ok"`
	ASNOK       bool   `json:"asn_ok"`
	LastSync    string `json:"last_sync,omitempty"`
}

func (s *Syncer) Status() Status {
	country := filepath.Join(s.DataDir, "GeoLite2-Country.mmdb")
	asn := filepath.Join(s.DataDir, "GeoLite2-ASN.mmdb")
	st := Status{
		CountryPath: country,
		ASNPath:     asn,
		CountryOK:   fileExists(country),
		ASNOK:       fileExists(asn),
	}
	if ts, err := os.Stat(filepath.Join(s.DataDir, ".last_sync")); err == nil {
		st.LastSync = ts.ModTime().UTC().Format(time.RFC3339)
	}
	return st
}

func (s *Syncer) Sync(ctx context.Context) error {
	if s.LicenseKey == "" {
		return fmt.Errorf("MAXMIND_LICENSE_KEY not configured")
	}
	if err := os.MkdirAll(s.DataDir, 0o755); err != nil {
		return err
	}

	if err := s.downloadEdition(ctx, editionCountry); err != nil {
		return fmt.Errorf("country: %w", err)
	}
	if err := s.downloadEdition(ctx, editionASN); err != nil {
		return fmt.Errorf("asn: %w", err)
	}

	return os.WriteFile(filepath.Join(s.DataDir, ".last_sync"), []byte(time.Now().UTC().Format(time.RFC3339)), 0o644)
}

func (s *Syncer) downloadEdition(ctx context.Context, edition string) error {
	target := filepath.Join(s.DataDir, edition+".mmdb")
	url := fmt.Sprintf(
		"https://download.maxmind.com/app/geoip_download?edition_id=%s&license_key=%s&suffix=tar.gz",
		edition, s.LicenseKey,
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	resp, err := s.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	gz, err := gzip.NewReader(resp.Body)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	found := false
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if hdr.Typeflag != tar.TypeReg {
			continue
		}
		if !strings.HasSuffix(hdr.Name, edition+".mmdb") {
			continue
		}

		out, err := os.Create(target)
		if err != nil {
			return err
		}
		if _, err := io.Copy(out, tr); err != nil {
			out.Close()
			return err
		}
		out.Close()
		found = true
		break
	}

	if !found {
		return fmt.Errorf("%s.mmdb not found in archive", edition)
	}

	return nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
