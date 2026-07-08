package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

type customRulesStatusResponse struct {
	SiteID          string                   `json:"site_id"`
	StageEnabled    bool                     `json:"stage_enabled"`
	ConfigEnabled   bool                     `json:"config_enabled"`
	RuleCount       int                      `json:"rule_count"`
	Rules           []map[string]interface{} `json:"rules_summary"`
	RuntimeFound    bool                     `json:"runtime_found"`
	RuntimeEnabled  bool                     `json:"runtime_enabled"`
	RuntimeRuleCount int                     `json:"runtime_rule_count"`
	RuntimeExprs    []string                 `json:"runtime_exprs"`
}

func (h *Handler) getCustomRulesStatus(c echo.Context) error {
	siteID := c.Param("id")

	if err := h.db.First(&db.Site{}, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var stage db.PipelineStage
	err := h.db.Where("site_id = ? AND module = ?", siteID, "custom_rules").First(&stage).Error
	if err != nil {
		return c.JSON(http.StatusOK, customRulesStatusResponse{
			SiteID:       siteID,
			StageEnabled: false,
			RuleCount:    0,
		})
	}

	cfg := map[string]interface{}{}
	if stage.Config != "" {
		_ = json.Unmarshal([]byte(stage.Config), &cfg)
	}

	ruleCount := 0
	summary := []map[string]interface{}{}
	if raw, ok := cfg["rules"].([]interface{}); ok {
		ruleCount = len(raw)
		for _, item := range raw {
			rule, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			expr := ""
			if match, ok := rule["match"].(map[string]interface{}); ok {
				if s, ok := match["expr"].(string); ok {
					expr = s
				}
			}
			summary = append(summary, map[string]interface{}{
				"id":      rule["id"],
				"name":    rule["name"],
				"enabled": rule["enabled"],
				"expr":    expr,
				"action":  rule["action"],
			})
		}
	}

	configEnabled := true
	if v, ok := cfg["enabled"].(bool); ok {
		configEnabled = v
	}

	resp := customRulesStatusResponse{
		SiteID:        siteID,
		StageEnabled:  stage.Enabled,
		ConfigEnabled: configEnabled,
		RuleCount:     ruleCount,
		Rules:         summary,
	}

	runtimePath := os.Getenv("BADSECTOR_RUNTIME")
	if runtimePath == "" {
		runtimePath = "/runtime"
	}
	data, readErr := os.ReadFile(filepath.Join(runtimePath, "sites.json"))
	if readErr != nil {
		return c.JSON(http.StatusOK, resp)
	}

	var sites []map[string]interface{}
	if json.Unmarshal(data, &sites) != nil {
		return c.JSON(http.StatusOK, resp)
	}

	for _, site := range sites {
		if fmt.Sprint(site["id"]) != siteID {
			continue
		}
		pipeline, _ := site["pipeline"].([]interface{})
		for _, rawStage := range pipeline {
			stageMap, ok := rawStage.(map[string]interface{})
			if !ok || stageMap["module"] != "custom_rules" {
				continue
			}
			resp.RuntimeFound = true
			if enabled, ok := stageMap["enabled"].(bool); ok {
				resp.RuntimeEnabled = enabled
			}
			stageCfg, _ := stageMap["config"].(map[string]interface{})
			if rules, ok := stageCfg["rules"].([]interface{}); ok {
				resp.RuntimeRuleCount = len(rules)
				for _, r := range rules {
					rule, ok := r.(map[string]interface{})
					if !ok {
						continue
					}
					if match, ok := rule["match"].(map[string]interface{}); ok {
						if expr, ok := match["expr"].(string); ok {
							resp.RuntimeExprs = append(resp.RuntimeExprs, expr)
						}
					}
				}
			}
		}
	}

	return c.JSON(http.StatusOK, resp)
}
