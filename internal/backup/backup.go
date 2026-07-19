package backup

import (
	"archive/zip"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/badsector/badsector/internal/db"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const FormatVersion = 1

// SecretKeys — backup/restore ile tasinan env anahtarlari.
var SecretKeys = []string{
	"BADSECTOR_JWT_SECRET",
	"BADSECTOR_ADMIN_USER",
	"BADSECTOR_ADMIN_PASSWORD",
	"BADSECTOR_CHALLENGE_SECRET",
	"BADSECTOR_ENGINE_ADMIN_TOKEN",
	"BADSECTOR_ACME_EMAIL",
	"BADSECTOR_ACME_STAGING",
	"BADSECTOR_HAPROXY_CONFIG",
	"BADSECTOR_TRUSTED_IPS",
	"BADSECTOR_CLOUDFLARE",
	"BADSECTOR_UI_PORT",
	"BADSECTOR_AUTH_DISABLED",
	"MAXMIND_LICENSE_KEY",
}

// AdminKeys — her backup'ta mutlaka (UX: restore sonrasi ayni login).
var AdminKeys = []string{
	"BADSECTOR_ADMIN_USER",
	"BADSECTOR_ADMIN_PASSWORD",
}

type Meta struct {
	FormatVersion int       `json:"format_version"`
	CreatedAt     time.Time `json:"created_at"`
	Hostname      string    `json:"hostname,omitempty"`
	HasSecrets    bool      `json:"has_secrets"`
	HasCerts      bool      `json:"has_certs"`
	SiteCount     int       `json:"site_count"`
	Notes         string    `json:"notes,omitempty"`
}

type DatabaseDump struct {
	Sites           []db.Site           `json:"sites"`
	Policies        []db.Policy         `json:"policies"`
	PipelineStages  []db.PipelineStage  `json:"pipeline_stages"`
	Certificates    []db.Certificate    `json:"certificates"`
}

type CreateOptions struct {
	CertsPath     string
	ChallengePath string // dir containing template.html
	IncludeSecrets bool
	Notes         string
}

type RestoreOptions struct {
	CertsPath     string
	ChallengePath string
	RestoreDir    string // write secrets.env here for host merge
	// SecretsMode: "keep" | "rotate" | "skip"
	SecretsMode   string
}

type RestoreResult struct {
	SitesRestored int               `json:"sites_restored"`
	CertFiles     int               `json:"cert_files"`
	SecretsMode   string            `json:"secrets_mode"`
	SecretsPath   string            `json:"secrets_path,omitempty"`
	Rotated       map[string]string `json:"rotated,omitempty"` // only when rotate — show once
	Message       string            `json:"message"`
}

func Create(database *gorm.DB, opts CreateOptions) ([]byte, error) {
	var dump DatabaseDump
	if err := database.Find(&dump.Sites).Error; err != nil {
		return nil, fmt.Errorf("sites: %w", err)
	}
	if err := database.Find(&dump.Policies).Error; err != nil {
		return nil, fmt.Errorf("policies: %w", err)
	}
	if err := database.Find(&dump.PipelineStages).Error; err != nil {
		return nil, fmt.Errorf("pipeline: %w", err)
	}
	if err := database.Find(&dump.Certificates).Error; err != nil {
		return nil, fmt.Errorf("certificates: %w", err)
	}

	buf := new(bytes.Buffer)
	zw := zip.NewWriter(buf)

	meta := Meta{
		FormatVersion: FormatVersion,
		CreatedAt:     time.Now().UTC(),
		Hostname:      hostname(),
		HasSecrets:    opts.IncludeSecrets,
		SiteCount:     len(dump.Sites),
		Notes:         opts.Notes,
	}

	dbJSON, err := json.MarshalIndent(dump, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := writeZipFile(zw, "db.json", dbJSON); err != nil {
		return nil, err
	}

	certCount := 0
	if opts.CertsPath != "" {
		n, err := addDirToZip(zw, opts.CertsPath, "certs")
		if err != nil {
			return nil, fmt.Errorf("certs: %w", err)
		}
		certCount = n
	}
	meta.HasCerts = certCount > 0

	if opts.ChallengePath != "" {
		tpl := filepath.Join(opts.ChallengePath, "template.html")
		if b, err := os.ReadFile(tpl); err == nil && len(b) > 0 {
			_ = writeZipFile(zw, "challenge/template.html", b)
		}
	}

	if opts.IncludeSecrets {
		sec := collectSecretsFromEnv(true)
		if err := writeZipFile(zw, "secrets.env", []byte(sec)); err != nil {
			return nil, err
		}
	} else {
		// Secrets kapali olsa bile admin login yedeklenir (UX).
		sec := collectSecretsFromEnv(false)
		if err := writeZipFile(zw, "secrets.env", []byte(sec)); err != nil {
			return nil, err
		}
		meta.HasSecrets = true
		meta.Notes = strings.TrimSpace(meta.Notes + " admin credentials included")
	}

	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := writeZipFile(zw, "meta.json", metaJSON); err != nil {
		return nil, err
	}

	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func Restore(database *gorm.DB, zipData []byte, opts RestoreOptions) (*RestoreResult, error) {
	zr, err := zip.NewReader(bytes.NewReader(zipData), int64(len(zipData)))
	if err != nil {
		return nil, fmt.Errorf("invalid zip: %w", err)
	}

	files := map[string]*zip.File{}
	for _, f := range zr.File {
		files[f.Name] = f
	}

	metaBytes, err := readZip(files, "meta.json")
	if err != nil {
		return nil, fmt.Errorf("meta.json missing: %w", err)
	}
	var meta Meta
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return nil, err
	}
	if meta.FormatVersion > FormatVersion {
		return nil, fmt.Errorf("backup format %d newer than this BadSector (%d)", meta.FormatVersion, FormatVersion)
	}

	dbBytes, err := readZip(files, "db.json")
	if err != nil {
		return nil, fmt.Errorf("db.json missing: %w", err)
	}
	var dump DatabaseDump
	if err := json.Unmarshal(dbBytes, &dump); err != nil {
		return nil, fmt.Errorf("db.json: %w", err)
	}

	err = database.Transaction(func(tx *gorm.DB) error {
		// Soft-delete dahil temizle (Unscoped)
		if err := tx.Unscoped().Where("1 = 1").Delete(&db.Certificate{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("1 = 1").Delete(&db.PipelineStage{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("1 = 1").Delete(&db.Policy{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("1 = 1").Delete(&db.Site{}).Error; err != nil {
			return err
		}

		for i := range dump.Sites {
			s := dump.Sites[i]
			s.DeletedAt = gorm.DeletedAt{}
			if err := tx.Clauses(clause.OnConflict{UpdateAll: true}).Create(&s).Error; err != nil {
				return fmt.Errorf("site %s: %w", s.ID, err)
			}
		}
		for i := range dump.Policies {
			p := dump.Policies[i]
			p.DeletedAt = gorm.DeletedAt{}
			if err := tx.Create(&p).Error; err != nil {
				return fmt.Errorf("policy %s: %w", p.ID, err)
			}
		}
		for i := range dump.PipelineStages {
			st := dump.PipelineStages[i]
			st.DeletedAt = gorm.DeletedAt{}
			if err := tx.Create(&st).Error; err != nil {
				return fmt.Errorf("pipeline %s: %w", st.ID, err)
			}
		}
		for i := range dump.Certificates {
			c := dump.Certificates[i]
			c.DeletedAt = gorm.DeletedAt{}
			if err := tx.Create(&c).Error; err != nil {
				return fmt.Errorf("cert %s: %w", c.ID, err)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	certFiles := 0
	if opts.CertsPath != "" {
		n, err := extractPrefix(files, "certs/", opts.CertsPath)
		if err != nil {
			return nil, fmt.Errorf("extract certs: %w", err)
		}
		certFiles = n
	}

	if opts.ChallengePath != "" {
		if b, err := readZip(files, "challenge/template.html"); err == nil && len(b) > 0 {
			_ = os.MkdirAll(opts.ChallengePath, 0o755)
			_ = os.WriteFile(filepath.Join(opts.ChallengePath, "template.html"), b, 0o600)
		}
	}

	mode := strings.ToLower(opts.SecretsMode)
	if mode == "" {
		mode = "keep"
	}
	result := &RestoreResult{
		SitesRestored: len(dump.Sites),
		CertFiles:     certFiles,
		SecretsMode:   mode,
	}

	secRaw, secErr := readZip(files, "secrets.env")
	switch mode {
	case "skip":
		result.Message = "DB + certs restored. Secrets skipped — copy .env manually or re-run with secrets_mode=keep|rotate."
	case "rotate":
		rotated := rotateSecrets(parseEnvFile(string(secRaw)))
		result.Rotated = rotated
		path, err := writeSecretsFile(opts.RestoreDir, formatEnv(rotated))
		if err != nil {
			return nil, err
		}
		result.SecretsPath = path
		result.Message = "DB + certs restored. Crypto secrets ROTATED; admin user/password kept from backup. Merge data/restore/secrets.env into .env and restart."
	case "keep":
		if secErr != nil || len(bytes.TrimSpace(secRaw)) == 0 {
			result.Message = "DB + certs restored. Backup had no secrets.env — copy host .env manually."
			result.SecretsMode = "missing"
		} else {
			path, err := writeSecretsFile(opts.RestoreDir, string(secRaw))
			if err != nil {
				return nil, err
			}
			result.SecretsPath = path
			result.Message = "DB + certs restored. Secrets kept from backup — merge into host .env and restart api/engine/haproxy/watcher."
		}
	default:
		return nil, fmt.Errorf("secrets_mode must be keep|rotate|skip")
	}

	return result, nil
}

func collectSecretsFromEnv(includeAll bool) string {
	var b strings.Builder
	b.WriteString("# BadSector backup secrets — KEEP PRIVATE\n")
	b.WriteString("# Generated " + time.Now().UTC().Format(time.RFC3339) + "\n")
	if !includeAll {
		b.WriteString("# Mode: admin-only (full secrets checkbox was off)\n")
	}
	b.WriteString("\n")

	keys := AdminKeys
	if includeAll {
		keys = SecretKeys
	}
	seen := map[string]bool{}
	for _, k := range keys {
		if seen[k] {
			continue
		}
		seen[k] = true
		v := os.Getenv(k)
		if v == "" && k == "BADSECTOR_ADMIN_USER" {
			v = "admin"
		}
		if v == "" {
			continue
		}
		b.WriteString(k)
		b.WriteString("=")
		b.WriteString(v)
		b.WriteString("\n")
	}
	return b.String()
}

func rotateSecrets(base map[string]string) map[string]string {
	out := map[string]string{}
	for _, k := range SecretKeys {
		if v, ok := base[k]; ok && v != "" {
			out[k] = v
		}
	}
	// Admin kullanici/sifre KORUNUR (UX). Sadece kripto token'lar yenilenir.
	out["BADSECTOR_JWT_SECRET"] = randomHex(32)
	out["BADSECTOR_CHALLENGE_SECRET"] = randomHex(32)
	out["BADSECTOR_ENGINE_ADMIN_TOKEN"] = randomHex(24)
	if out["BADSECTOR_ADMIN_USER"] == "" {
		out["BADSECTOR_ADMIN_USER"] = "admin"
	}
	if out["BADSECTOR_ADMIN_PASSWORD"] == "" {
		out["BADSECTOR_ADMIN_PASSWORD"] = randomHex(16)
	}
	if out["BADSECTOR_AUTH_DISABLED"] == "" {
		out["BADSECTOR_AUTH_DISABLED"] = "false"
	}
	if out["BADSECTOR_CLOUDFLARE"] == "" {
		out["BADSECTOR_CLOUDFLARE"] = "false"
	}
	if out["BADSECTOR_HAPROXY_CONFIG"] == "" {
		out["BADSECTOR_HAPROXY_CONFIG"] = "live"
	}
	return out
}

func parseEnvFile(s string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i <= 0 {
			continue
		}
		k := strings.TrimSpace(line[:i])
		v := strings.TrimSpace(line[i+1:])
		out[k] = v
	}
	return out
}

func formatEnv(m map[string]string) string {
	var b strings.Builder
	b.WriteString("# BadSector restored secrets — merge into host .env then: docker compose up -d\n")
	b.WriteString("# KEEP PRIVATE\n\n")
	for _, k := range SecretKeys {
		if v, ok := m[k]; ok && v != "" {
			b.WriteString(k)
			b.WriteString("=")
			b.WriteString(v)
			b.WriteString("\n")
		}
	}
	return b.String()
}

func writeSecretsFile(dir, content string) (string, error) {
	if dir == "" {
		dir = "/data/restore"
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "secrets.env")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		return "", err
	}
	return path, nil
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func hostname() string {
	h, _ := os.Hostname()
	return h
}

func writeZipFile(zw *zip.Writer, name string, data []byte) error {
	w, err := zw.Create(name)
	if err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}

func addDirToZip(zw *zip.Writer, root, prefix string) (int, error) {
	count := 0
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err := writeZipFile(zw, prefix+"/"+rel, data); err != nil {
			return err
		}
		count++
		return nil
	})
	return count, err
}

func readZip(files map[string]*zip.File, name string) ([]byte, error) {
	f := files[name]
	if f == nil {
		return nil, fmt.Errorf("%s not found", name)
	}
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	return io.ReadAll(rc)
}

func extractPrefix(files map[string]*zip.File, prefix, destRoot string) (int, error) {
	count := 0
	for name, f := range files {
		if !strings.HasPrefix(name, prefix) || strings.HasSuffix(name, "/") {
			continue
		}
		rel := strings.TrimPrefix(name, prefix)
		if rel == "" || strings.Contains(rel, "..") {
			continue
		}
		target := filepath.Join(destRoot, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return count, err
		}
		rc, err := f.Open()
		if err != nil {
			return count, err
		}
		data, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			return count, err
		}
		mode := os.FileMode(0o600)
		if strings.HasSuffix(rel, ".pem") || strings.HasSuffix(rel, ".crt") {
			mode = 0o644
		}
		if err := os.WriteFile(target, data, mode); err != nil {
			return count, err
		}
		count++
	}
	return count, nil
}
