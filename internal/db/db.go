package db

import (
	"strings"

	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func Connect(url string) (*gorm.DB, error) {
	var dialector gorm.Dialector

	switch {
	case strings.HasPrefix(url, "postgres://"), strings.HasPrefix(url, "postgresql://"):
		dialector = postgres.Open(url)
	default:
		path := strings.TrimPrefix(url, "sqlite://")
		dialector = sqlite.Open(path)
	}

	return gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
}

func Migrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&Site{},
		&Policy{},
		&PipelineStage{},
		&Certificate{},
	)
}
