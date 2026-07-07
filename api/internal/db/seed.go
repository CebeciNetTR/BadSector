package db

import (
	"encoding/json"

	"gorm.io/gorm"
)

// SeedDefault creates a demo site with pipeline if the database is empty.
func SeedDefault(db *gorm.DB) error {
	var count int64
	if err := db.Model(&Site{}).Count(&count).Error; err != nil {
		return err
	}
	if count > 0 {
		return nil
	}

	hosts, _ := json.Marshal([]string{"localhost", "127.0.0.1"})
	settings, _ := json.Marshal(map[string]interface{}{
		"live_trace":  true,
		"debug_trace": false,
	})

	site := Site{
		ID:       NewID(),
		Name:     "Default Site",
		Hosts:    string(hosts),
		Settings: string(settings),
		Enabled:  true,
	}

	if err := db.Create(&site).Error; err != nil {
		return err
	}

	stages := db.DefaultPipelineStages(site.ID)

	return db.Create(&stages).Error
}
