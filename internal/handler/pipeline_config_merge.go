package handler

import "encoding/json"

// mergeStageConfig keeps module-specific settings when the Pipeline UI sends stale/empty config.
// Pipeline page only edits order/enabled; Security Modules pages own detailed config.
// Existing non-empty config always wins — UI DEFAULT_MODULE_CONFIG placeholders must not wipe GeoIP etc.
func mergeStageConfig(module, incoming, existing string) string {
	_ = module
	if existing != "" {
		return existing
	}
	return incoming
}

// syncConfigEnabled mirrors pipeline stage Enabled into config.enabled when that key exists
// (or for modules that commonly use it), so Security Modules toggles stay consistent.
func syncConfigEnabled(configJSON string, enabled bool) string {
	if configJSON == "" {
		return configJSON
	}
	var cfg map[string]interface{}
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return configJSON
	}
	if _, has := cfg["enabled"]; has {
		cfg["enabled"] = enabled
		out, err := json.Marshal(cfg)
		if err != nil {
			return configJSON
		}
		return string(out)
	}
	return configJSON
}
