package runtime

import (
	"fmt"
	"io"
	"net/http"
	"time"

	"gorm.io/gorm"
)

type EngineReloader struct {
	url   string
	token string
}

func NewEngineReloader(url, token string) *EngineReloader {
	return &EngineReloader{url: url, token: token}
}

func (r *EngineReloader) Reload() error {
	if r == nil || r.url == "" {
		return nil
	}

	req, err := http.NewRequest(http.MethodPost, r.url, nil)
	if err != nil {
		return err
	}

	if r.token != "" {
		req.Header.Set("Authorization", "Bearer "+r.token)
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("engine reload request: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)

	if resp.StatusCode >= 300 {
		return fmt.Errorf("engine reload failed: HTTP %d", resp.StatusCode)
	}
	return nil
}

// GenerateAndReload writes sites.json and notifies the engine.
func (g *Generator) GenerateAndReload(database *gorm.DB, reloader *EngineReloader) error {
	if err := g.GenerateAll(database); err != nil {
		return err
	}
	if reloader != nil {
		if err := reloader.Reload(); err != nil {
			return err
		}
	}
	return nil
}
