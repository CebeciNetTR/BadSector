package handler

import "encoding/json"

// mergeStageConfig keeps module-specific settings when the Pipeline UI sends stale/empty config.
// Pipeline page only edits order/enabled; Security Modules pages own detailed config.
func mergeStageConfig(module, incoming, existing string) string {
	if incoming == "" {
		if existing != "" {
			return existing
		}
		return incoming
	}
	if existing == "" {
		return incoming
	}

	switch module {
	case "custom_rules", "policies", "rate_limiter":
		inCount := ruleCount(incoming)
		exCount := ruleCount(existing)
		if inCount == 0 && exCount > 0 {
			return existing
		}
		if module == "custom_rules" && isDefaultEmptyCustomRules(incoming) && exCount > 0 {
			return existing
		}
	}

	return incoming
}

func ruleCount(configJSON string) int {
	var cfg map[string]interface{}
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return 0
	}
	rules, ok := cfg["rules"].([]interface{})
	if !ok || rules == nil {
		return 0
	}
	return len(rules)
}

func isDefaultEmptyCustomRules(configJSON string) bool {
	var cfg map[string]interface{}
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return false
	}
	rules, ok := cfg["rules"].([]interface{})
	if !ok {
		return false
	}
	return len(rules) == 0
}
