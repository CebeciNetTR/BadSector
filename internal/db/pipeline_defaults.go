package db

import (
	"encoding/json"
	"os"

	"gorm.io/gorm"
)

const reverseProxyModule = "reverse_proxy"

const localBackendURL = "http://127.0.0.1:8081"
const dockerBackendURL = "http://backend:80"

// DefaultBackendURL returns the upstream URL for new sites.
// Override with BADSECTOR_DEFAULT_BACKEND_URL (Docker compose uses http://backend:80).
func DefaultBackendURL() string {
	if v := os.Getenv("BADSECTOR_DEFAULT_BACKEND_URL"); v != "" {
		return v
	}
	return localBackendURL
}

// DefaultPipelineStages returns the standard module pipeline for a new site.
func DefaultPipelineStages(siteID string) []PipelineStage {
	backendURL := DefaultBackendURL()

	rateConfig, _ := json.Marshal(map[string]interface{}{
		"use_redis": true,
		"fail_mode": "open",
		"redis":     map[string]interface{}{"host": "redis", "port": 6379, "timeout": 100},
		"rules":     []interface{}{},
	})

	proxyConfig, _ := json.Marshal(map[string]interface{}{
		"upstream":    "backend",
		"backend_url": backendURL,
	})

	wafConfig, _ := json.Marshal(map[string]interface{}{
		"ruleset":        "coraza-crs",
		"paranoia_level": 1,
		"mode":           "block",
		"exclude_paths":  []string{"/badsector/health"},
		"audit":          true,
		"rules_dir":      "/etc/badsector/coraza/rules",
	})

	trustedBotsConfig, _ := json.Marshal(map[string]interface{}{
		"enabled":      true,
		"mark_trusted": true,
		"verify_ip":    true,
		// Dogrulanmis bot'u tum korumalardan (WAF dahil) muaf tut ve dogrudan
		// backend'e gecir. Hem guvenli (forward-confirmed rDNS) hem ucuz.
		"bypass_pipeline": true,
	})

	ipRepConfig, _ := json.Marshal(map[string]interface{}{
		"enabled":        true,
		"block_ips":      []interface{}{},
		"block_cidrs":    []interface{}{},
		"use_redis_feed": false,
		"redis_key":      "badsector:reputation:bad",
		"fail_open":      true,
	})

	geoipConfig, _ := json.Marshal(map[string]interface{}{
		"database_path":       "/etc/badsector/geoip/GeoLite2-Country.mmdb",
		"fail_open":           true,
		"block_countries":     []interface{}{},
		"allow_countries":     []interface{}{},
		"allow_only":          false,
		"use_header_fallback": true,
		"deny_action":         "block",
	})

	customRulesConfig, _ := json.Marshal(map[string]interface{}{
		"enabled":   false,
		"fail_open": true,
		"rules":     []interface{}{},
	})

	return []PipelineStage{
		{ID: NewID(), SiteID: siteID, Module: "access_lists", Order: 0, Enabled: true, Config: `{"deny":[],"allow":[]}`},
		{ID: NewID(), SiteID: siteID, Module: "trusted_bots", Order: 1, Enabled: true, Config: string(trustedBotsConfig)},
		{ID: NewID(), SiteID: siteID, Module: "ip_reputation", Order: 2, Enabled: true, Config: string(ipRepConfig)},
		{ID: NewID(), SiteID: siteID, Module: "geoip", Order: 3, Enabled: true, Config: string(geoipConfig)},
		{ID: NewID(), SiteID: siteID, Module: "policies", Order: 4, Enabled: true, Config: `{"rules":[]}`},
		{ID: NewID(), SiteID: siteID, Module: "rate_limiter", Order: 5, Enabled: true, Config: string(rateConfig)},
		{ID: NewID(), SiteID: siteID, Module: "managed_waf", Order: 6, Enabled: false, Config: string(wafConfig)},
		{ID: NewID(), SiteID: siteID, Module: "custom_rules", Order: 7, Enabled: false, Config: string(customRulesConfig)},
		{ID: NewID(), SiteID: siteID, Module: reverseProxyModule, Order: 8, Enabled: true, Config: string(proxyConfig)},
	}
}

// GetBackendURL reads backend_url from reverse_proxy stage config.
func GetBackendURL(configJSON string) string {
	if configJSON == "" {
		return DefaultBackendURL()
	}
	var cfg map[string]interface{}
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return DefaultBackendURL()
	}
	if url, ok := cfg["backend_url"].(string); ok && url != "" {
		return url
	}
	if upstream, ok := cfg["upstream"].(string); ok && upstream != "" {
		return "http://" + upstream
	}
	return DefaultBackendURL()
}

// SetBackendURL updates reverse_proxy stage config for a site.
func SetBackendURL(db *gorm.DB, siteID, backendURL string) error {
	var stage PipelineStage
	err := db.Where("site_id = ? AND module = ?", siteID, reverseProxyModule).First(&stage).Error
	if err != nil {
		return err
	}

	cfg := map[string]interface{}{
		"upstream":    "backend",
		"backend_url": backendURL,
	}
	if stage.Config != "" {
		_ = json.Unmarshal([]byte(stage.Config), &cfg)
	}
	cfg["backend_url"] = backendURL

	data, _ := json.Marshal(cfg)
	stage.Config = string(data)
	return db.Save(&stage).Error
}

// DockerBackendURL is the compose service upstream (for docs/tests).
func DockerBackendURL() string {
	return dockerBackendURL
}
