package db

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Site struct {
	ID        string         `gorm:"primaryKey" json:"id"`
	Name      string         `gorm:"not null" json:"name"`
	Hosts     string         `gorm:"type:text" json:"hosts"` // JSON array
	Settings  string         `gorm:"type:text" json:"settings"`
	Enabled   bool           `gorm:"default:true" json:"enabled"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	Policies []Policy         `gorm:"foreignKey:SiteID" json:"policies,omitempty"`
	Pipeline []PipelineStage  `gorm:"foreignKey:SiteID" json:"pipeline,omitempty"`
}

type Policy struct {
	ID         string         `gorm:"primaryKey" json:"id"`
	SiteID     string         `gorm:"index;not null" json:"site_id"`
	Name       string         `gorm:"not null" json:"name"`
	Priority   int            `gorm:"default:100" json:"priority"`
	Enabled    bool           `gorm:"default:true" json:"enabled"`
	Conditions string         `gorm:"type:text" json:"conditions"` // JSON
	Actions    string         `gorm:"type:text" json:"actions"`    // JSON
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

type PipelineStage struct {
	ID        string         `gorm:"primaryKey" json:"id"`
	SiteID    string         `gorm:"index;not null" json:"site_id"`
	Module    string         `gorm:"not null" json:"module"`
	Order     int            `gorm:"not null" json:"order"`
	Enabled   bool           `gorm:"default:true" json:"enabled"`
	Config    string         `gorm:"type:text" json:"config"` // JSON
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

type Certificate struct {
	ID            string         `gorm:"primaryKey" json:"id"`
	SiteID        string         `gorm:"index" json:"site_id"`
	Domain        string         `gorm:"not null;index" json:"domain"`
	Email         string         `json:"email"`
	Issuer        string         `json:"issuer"`
	Status        string         `gorm:"default:pending" json:"status"`
	AutoRenew     bool           `gorm:"default:true" json:"auto_renew"`
	ExpiresAt     *time.Time     `json:"expires_at,omitempty"`
	LastRenewedAt *time.Time     `json:"last_renewed_at,omitempty"`
	LastError     string         `gorm:"type:text" json:"last_error,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

const (
	CertStatusPending  = "pending"
	CertStatusActive   = "active"
	CertStatusExpired  = "expired"
	CertStatusError    = "error"
	CertStatusRenewing = "renewing"
)

func NewID() string {
	return uuid.New().String()
}
