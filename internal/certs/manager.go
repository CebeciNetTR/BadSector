package certs

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/badsector/badsector/internal/db"
	"github.com/go-acme/lego/v4/certcrypto"
	"github.com/go-acme/lego/v4/certificate"
	"github.com/go-acme/lego/v4/lego"
	"github.com/go-acme/lego/v4/registration"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"
)

const renewBefore = 30 * 24 * time.Hour

type Manager struct {
	db          *gorm.DB
	redis       *redis.Client
	certDir     string
	defaultMail string
	staging     bool
	reloadCmd   string
}

func NewManager(database *gorm.DB, redisURL, certDir, defaultEmail string, staging bool, reloadCmd string) (*Manager, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, err
	}

	if err := os.MkdirAll(certDir, 0o755); err != nil {
		return nil, err
	}

	return &Manager{
		db:          database,
		redis:       redis.NewClient(opts),
		certDir:     certDir,
		defaultMail: defaultEmail,
		staging:     staging,
		reloadCmd:   reloadCmd,
	}, nil
}

type acmeUser struct {
	Email        string                 `json:"email"`
	Registration *registration.Resource `json:"registration"`
	keyPEM       string                 `json:"key_pem"`
	privateKey   crypto.PrivateKey      `json:"-"`
}

func (u *acmeUser) GetEmail() string                        { return u.Email }
func (u *acmeUser) GetRegistration() *registration.Resource { return u.Registration }
func (u *acmeUser) GetPrivateKey() crypto.PrivateKey        { return u.privateKey }

func (m *Manager) Issue(ctx context.Context, certID string) error {
	var record db.Certificate
	if err := m.db.First(&record, "id = ?", certID).Error; err != nil {
		return err
	}
	return m.issueRecord(ctx, &record)
}

func (m *Manager) Renew(ctx context.Context, certID string) error {
	var record db.Certificate
	if err := m.db.First(&record, "id = ?", certID).Error; err != nil {
		return err
	}
	record.Status = db.CertStatusRenewing
	record.LastError = ""
	_ = m.db.Save(&record).Error
	return m.issueRecord(ctx, &record)
}

func (m *Manager) RenewDue(ctx context.Context) (int, error) {
	var certs []db.Certificate
	if err := m.db.Where("auto_renew = ? AND status IN ?", true, []string{db.CertStatusActive, db.CertStatusExpired, db.CertStatusError}).
		Find(&certs).Error; err != nil {
		return 0, err
	}

	renewed := 0
	now := time.Now()
	for i := range certs {
		cert := certs[i]
		if cert.ExpiresAt != nil && cert.ExpiresAt.Sub(now) > renewBefore {
			continue
		}
		if err := m.Renew(ctx, cert.ID); err != nil {
			continue
		}
		renewed++
	}
	return renewed, nil
}

func (m *Manager) DeleteFiles(domain string) error {
	base := sanitizeDomain(domain)
	for _, name := range []string{base + ".pem", base + ".crt", base + ".key"} {
		_ = os.Remove(filepath.Join(m.certDir, name))
	}
	return nil
}

func (m *Manager) issueRecord(ctx context.Context, record *db.Certificate) error {
	email := strings.TrimSpace(record.Email)
	if email == "" {
		email = m.defaultMail
	}
	if email == "" {
		return fmt.Errorf("ACME email required (set on certificate or BADSECTOR_ACME_EMAIL)")
	}

	record.Status = db.CertStatusPending
	record.LastError = ""
	_ = m.db.Save(record).Error

	client, err := m.legoClient(email)
	if err != nil {
		return m.fail(record, err)
	}

	provider := &RedisHTTPProvider{client: m.redis}
	if err := client.Challenge.SetHTTP01Provider(provider); err != nil {
		return m.fail(record, err)
	}

	req := certificate.ObtainRequest{
		Domains: []string{record.Domain},
		Bundle:  true,
	}

	certRes, err := client.Certificate.Obtain(req)
	if err != nil {
		return m.fail(record, err)
	}

	if err := m.writePEM(record.Domain, certRes.Certificate, certRes.PrivateKey); err != nil {
		return m.fail(record, err)
	}

	expires := parseCertExpiry(certRes.Certificate)
	now := time.Now()
	record.Status = db.CertStatusActive
	record.Issuer = "Let's Encrypt"
	record.LastError = ""
	record.LastRenewedAt = &now
	record.ExpiresAt = &expires
	if err := m.db.Save(record).Error; err != nil {
		return err
	}

	if m.reloadCmd != "" {
		_ = m.runReloadCmd()
	}

	return nil
}

func (m *Manager) fail(record *db.Certificate, err error) error {
	record.Status = db.CertStatusError
	record.LastError = err.Error()
	_ = m.db.Save(record).Error
	return err
}

func (m *Manager) legoClient(email string) (*lego.Client, error) {
	user, err := m.loadOrCreateUser(email)
	if err != nil {
		return nil, err
	}

	config := lego.NewConfig(user)
	config.Certificate.KeyType = certcrypto.EC256
	if m.staging {
		config.CADirURL = lego.LEDirectoryStaging
	}

	client, err := lego.NewClient(config)
	if err != nil {
		return nil, err
	}

	if user.Registration == nil {
		reg, err := client.Registration.Register(registration.RegisterOptions{TermsOfServiceAgreed: true})
		if err != nil {
			return nil, err
		}
		user.Registration = reg
		if err := m.saveUser(user); err != nil {
			return nil, err
		}
	}

	return client, nil
}

func (m *Manager) accountPath(email string) string {
	safe := strings.NewReplacer("@", "_at_", ".", "_").Replace(strings.ToLower(email))
	return filepath.Join(m.certDir, "acme-"+safe+".json")
}

func (m *Manager) loadOrCreateUser(email string) (*acmeUser, error) {
	path := m.accountPath(email)
	if data, err := os.ReadFile(path); err == nil {
		var user acmeUser
		if err := json.Unmarshal(data, &user); err != nil {
			return nil, err
		}
		block, _ := pem.Decode([]byte(user.keyPEM))
		if block == nil {
			return nil, fmt.Errorf("invalid account key")
		}
		key, err := x509.ParseECPrivateKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		user.privateKey = key
		user.Email = email
		return &user, nil
	}

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}

	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return nil, err
	}
	keyPEM := string(pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}))

	return &acmeUser{
		Email:      email,
		keyPEM:     keyPEM,
		privateKey: key,
	}, nil
}

func (m *Manager) saveUser(user *acmeUser) error {
	data, err := json.Marshal(user)
	if err != nil {
		return err
	}
	return os.WriteFile(m.accountPath(user.Email), data, 0o600)
}

func (m *Manager) writePEM(domain string, certPEM, keyPEM []byte) error {
	base := sanitizeDomain(domain)
	certPath := filepath.Join(m.certDir, base+".crt")
	keyPath := filepath.Join(m.certDir, base+".key")
	pemPath := filepath.Join(m.certDir, base+".pem")

	if err := os.WriteFile(certPath, certPEM, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		return err
	}

	combined := append(append(certPEM, '\n'), keyPEM...)
	return os.WriteFile(pemPath, combined, 0o600)
}

func (m *Manager) runReloadCmd() error {
	parts := strings.Fields(m.reloadCmd)
	if len(parts) == 0 {
		return nil
	}
	cmd := exec.Command(parts[0], parts[1:]...)
	return cmd.Run()
}

func sanitizeDomain(domain string) string {
	return strings.NewReplacer("*", "_", ":", "_").Replace(strings.ToLower(domain))
}

func parseCertExpiry(certPEM []byte) time.Time {
	block, _ := pem.Decode(certPEM)
	if block == nil {
		return time.Now().Add(90 * 24 * time.Hour)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil || cert.NotAfter.IsZero() {
		return time.Now().Add(90 * 24 * time.Hour)
	}
	return cert.NotAfter
}

type RedisHTTPProvider struct {
	client *redis.Client
}

func (p *RedisHTTPProvider) Present(domain, token, keyAuth string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return p.client.Set(ctx, "badsector:acme:"+token, keyAuth, 15*time.Minute).Err()
}

func (p *RedisHTTPProvider) CleanUp(domain, token, keyAuth string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return p.client.Del(ctx, "badsector:acme:"+token).Err()
}
