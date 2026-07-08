package runtime

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/badsector/badsector/internal/db"
	"gorm.io/gorm"
)

type Generator struct {
	path string
}

type RuntimeSite struct {
	ID       string                   `json:"id"`
	Name     string                   `json:"name"`
	Hosts    []string                 `json:"hosts"`
	Settings map[string]interface{}   `json:"settings"`
	Pipeline []RuntimePipelineStage   `json:"pipeline"`
}

type RuntimePipelineStage struct {
	Module  string                 `json:"module"`
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func NewGenerator(path string) *Generator {
	return &Generator{path: path}
}

func (g *Generator) GenerateAll(database *gorm.DB) error {
	var siteIDs []string
	if err := database.Model(&db.Site{}).Pluck("id", &siteIDs).Error; err != nil {
		return err
	}
	for _, siteID := range siteIDs {
		if err := db.NormalizePipelineOrder(database, siteID); err != nil {
			return err
		}
	}

	sites, err := g.compileAll(database)
	if err != nil {
		return err
	}
	return g.writeSites(sites)
}

func (g *Generator) GenerateAndReload(database *gorm.DB, reloader *EngineReloader) error {
	if err := g.GenerateAll(database); err != nil {
		return err
	}
	if reloader != nil {
		return reloader.Reload()
	}
	return nil
}

func (g *Generator) compileAll(database *gorm.DB) ([]RuntimeSite, error) {
	var dbSites []db.Site
	if err := database.Where("enabled = ?", true).Find(&dbSites).Error; err != nil {
		return nil, err
	}

	out := make([]RuntimeSite, 0, len(dbSites))
	for _, site := range dbSites {
		compiled, err := g.compileSite(database, site)
		if err != nil {
			return nil, fmt.Errorf("site %s: %w", site.ID, err)
		}
		out = append(out, compiled)
	}
	return out, nil
}

func (g *Generator) compileSite(database *gorm.DB, site db.Site) (RuntimeSite, error) {
	hosts := []string{}
	if site.Hosts != "" {
		_ = json.Unmarshal([]byte(site.Hosts), &hosts)
	}

	settings := map[string]interface{}{}
	if site.Settings != "" {
		_ = json.Unmarshal([]byte(site.Settings), &settings)
	}

	var stages []db.PipelineStage
	if err := database.Where("site_id = ?", site.ID).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return RuntimeSite{}, err
	}

	pipeline := make([]RuntimePipelineStage, 0, len(stages))
	for _, stage := range stages {
		cfg := map[string]interface{}{}
		if stage.Config != "" {
			_ = json.Unmarshal([]byte(stage.Config), &cfg)
		}

		if stage.Module == "policies" {
			rules, err := g.compilePolicies(database, site.ID)
			if err != nil {
				return RuntimeSite{}, err
			}
			cfg["rules"] = rules
		}

		if stage.Module == "custom_rules" {
			sanitizeCustomRulesConfig(cfg)
		}

		pipeline = append(pipeline, RuntimePipelineStage{
			Module:  stage.Module,
			Enabled: stage.Enabled,
			Config:  cfg,
		})
	}

	return RuntimeSite{
		ID:       site.ID,
		Name:     site.Name,
		Hosts:    hosts,
		Settings: settings,
		Pipeline: pipeline,
	}, nil
}

func (g *Generator) compilePolicies(database *gorm.DB, siteID string) ([]map[string]interface{}, error) {
	var policies []db.Policy
	if err := database.Where("site_id = ?", siteID).Order("priority asc").Find(&policies).Error; err != nil {
		return nil, err
	}

	rules := make([]map[string]interface{}, 0, len(policies))
	for _, policy := range policies {
		var conditions interface{}
		var actions []interface{}

		if policy.Conditions != "" {
			_ = json.Unmarshal([]byte(policy.Conditions), &conditions)
		}
		if policy.Actions != "" {
			_ = json.Unmarshal([]byte(policy.Actions), &actions)
		}

		rules = append(rules, map[string]interface{}{
			"id":         policy.ID,
			"name":       policy.Name,
			"enabled":    policy.Enabled,
			"priority":   policy.Priority,
			"conditions": conditions,
			"actions":    actions,
		})
	}
	return rules, nil
}

// Strip UI-only fields (_builder) from custom rule matches before engine runtime.
func sanitizeCustomRulesConfig(cfg map[string]interface{}) {
	rawRules, ok := cfg["rules"].([]interface{})
	if !ok {
		return
	}
	for _, raw := range rawRules {
		rule, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		match, ok := rule["match"].(map[string]interface{})
		if !ok {
			continue
		}
		delete(match, "_builder")
	}
}

func (g *Generator) writeSites(sites []RuntimeSite) error {
	if err := os.MkdirAll(g.path, 0o755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(sites, "", "  ")
	if err != nil {
		return err
	}

	target := filepath.Join(g.path, "sites.json")
	tmp := target + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}

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
		return fmt.Errorf("engine reload status: %d", resp.StatusCode)
	}
	return nil
}
