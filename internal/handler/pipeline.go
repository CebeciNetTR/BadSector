package handler

import (
	"encoding/json"
	"net/http"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

type pipelineStageInput struct {
	Module  string `json:"module"`
	Enabled bool   `json:"enabled"`
	Config  string `json:"config"`
}

func (h *Handler) getPipeline(c echo.Context) error {
	var stages []db.PipelineStage
	if err := h.db.Where("site_id = ?", c.Param("id")).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, stages)
}

func (h *Handler) updatePipeline(c echo.Context) error {
	siteID := c.Param("id")

	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var input []pipelineStageInput
	if err := c.Bind(&input); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	if len(input) == 0 {
		return echo.NewHTTPError(http.StatusBadRequest, "pipeline cannot be empty")
	}

	// reverse_proxy must be last when present
	for i, stage := range input {
		if stage.Module == "reverse_proxy" && i != len(input)-1 {
			return echo.NewHTTPError(http.StatusBadRequest, "reverse_proxy must be the last module")
		}
	}

	var existing []db.PipelineStage
	if err := h.db.Where("site_id = ?", siteID).Find(&existing).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	existingConfig := map[string]string{}
	for _, stage := range existing {
		existingConfig[stage.Module] = stage.Config
	}

	if err := h.db.Where("site_id = ?", siteID).Delete(&db.PipelineStage{}).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	stages := make([]db.PipelineStage, 0, len(input))
	for i, in := range input {
		cfg := ""
		// Pipeline UI only controls order/enabled — never overwrite module config from stale browser defaults.
		if existing, ok := existingConfig[in.Module]; ok && existing != "" {
			cfg = mergeStageConfig(in.Module, in.Config, existing)
		} else if in.Config != "" {
			cfg = in.Config
		}
		if cfg == "" {
			cfg = defaultModuleConfig(in.Module)
		}
		// Keep config.enabled in sync with pipeline stage (Security Modules pages read both).
		cfg = syncConfigEnabled(cfg, in.Enabled)

		stages = append(stages, db.PipelineStage{
			ID:      db.NewID(),
			SiteID:  siteID,
			Module:  in.Module,
			Order:   i,
			Enabled: in.Enabled,
			Config:  cfg,
		})
	}

	// GORM: bool zero-value (false) + gorm:"default:true" -> DB'ye yazilmaz, true kalir.
	// Select ile Enabled alanini zorla yazdiriyoruz (tik kaldirma bug'i).
	if err := h.db.Select("ID", "SiteID", "Module", "Order", "Enabled", "Config").Create(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	if err := db.NormalizePipelineOrder(h.db, siteID); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	if err := h.regenerate(); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, "runtime reload failed: "+err.Error())
	}
	return c.JSON(http.StatusOK, stages)
}

func defaultModuleConfig(module string) string {
	proxyCfg, _ := json.Marshal(map[string]string{
		"upstream":    "backend",
		"backend_url": db.DefaultBackendURL(),
	})

	defaults := map[string]string{
		"access_lists":      `{"deny":[],"allow":[]}`,
		"policies":          `{"rules":[]}`,
		"rate_limiter":      `{"use_redis":true,"fail_mode":"open","redis":{"host":"redis","port":6379,"timeout":100},"rules":[]}`,
		"reverse_proxy":     string(proxyCfg),
		"geoip":             `{"database_path":"/etc/badsector/geoip/GeoLite2-Country.mmdb","fail_open":true,"block_countries":[],"allow_countries":[],"allow_only":false,"use_header_fallback":true,"deny_action":"block","attack_deny_action":"drop","attack_block_countries":[],"ban_threshold":5,"ban_ttl":86400,"pass_ttl":3600}`,
		"trusted_bots":      `{"enabled":true,"mark_trusted":true,"verify_ip":true}`,
		"ip_reputation":     `{"enabled":true,"block_ips":[],"block_cidrs":[],"use_redis_feed":false,"fail_open":true}`,
		"asn":               `{"enabled":true,"database_path":"/etc/badsector/geoip/GeoLite2-ASN.mmdb","block_asns":[],"allow_asns":[],"allow_only":false,"ip_map":{},"fail_open":true,"attack_deny_action":"drop","attack_block_asns":[]}`,
		"header_validation": `{"enabled":true,"required":[],"forbidden":[],"rules":[]}`,
		"custom_rules":      `{"enabled":true,"fail_open":true,"rules":[]}`,
		"burst_detection":   `{"enabled":true,"window":10,"threshold":50,"key_by":"ip","paths":["/*"],"action":"rate_limit","fail_open":true}`,
		"js_challenge":      `{"enabled":false,"paths":["/*"],"exclude_paths":["/badsector/*","/favicon.ico","/robots.txt"],"pass_cookie":"bs_pass","pow_cookie":"bs_pow","difficulty":4,"difficulty_attack":5,"pass_ttl":3600,"ban_threshold":5,"ban_ttl":86400}`,
		"cookie_challenge":  `{"enabled":false,"paths":["/*"],"exclude_paths":["/badsector/*"],"cookie_name":"bs_verified","cookie_ttl":86400}`,
		"threat_intel":      `{"enabled":true,"redis_key":"badsector:threat_intel:bad","fail_open":true}`,
		"cache":             `{"enabled":false,"ttl":60}`,
		"managed_waf":      `{"ruleset":"coraza-crs","paranoia_level":1,"mode":"block","exclude_paths":["/badsector/health"],"audit":true,"rules_dir":"/etc/badsector/coraza/rules"}`,
	}

	if cfg, ok := defaults[module]; ok {
		return cfg
	}
	return `{}`
}
