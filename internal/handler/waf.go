package handler

import (
	"encoding/json"
	"net/http"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

const managedWafModule = "managed_waf"

func DefaultManagedWafConfig() map[string]interface{} {
	return map[string]interface{}{
		"ruleset":        "coraza-crs",
		"paranoia_level": 1,
		"mode":           "block",
		"exclude_paths":  []string{"/badsector/health"},
		"audit":          true,
		"rules_dir":      "/etc/badsector/coraza/rules",
	}
}

type managedWafResponse struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func (h *Handler) getManagedWaf(c echo.Context) error {
	siteID := c.Param("id")

	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var stages []db.PipelineStage
	if err := h.db.Where("site_id = ?", siteID).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	for _, stage := range stages {
		if stage.Module != managedWafModule {
			continue
		}

		cfg := DefaultManagedWafConfig()
		if stage.Config != "" {
			_ = json.Unmarshal([]byte(stage.Config), &cfg)
		}

		return c.JSON(http.StatusOK, managedWafResponse{
			Enabled: stage.Enabled,
			Config:  cfg,
		})
	}

	return c.JSON(http.StatusOK, managedWafResponse{
		Enabled: false,
		Config:  DefaultManagedWafConfig(),
	})
}

type updateManagedWafRequest struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func (h *Handler) updateManagedWaf(c echo.Context) error {
	siteID := c.Param("id")

	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var req updateManagedWafRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if req.Config == nil {
		req.Config = DefaultManagedWafConfig()
	}

	configJSON, err := json.Marshal(req.Config)
	if err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	var stages []db.PipelineStage
	if err := h.db.Where("site_id = ?", siteID).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	found := false
	for i := range stages {
		if stages[i].Module != managedWafModule {
			continue
		}

		stages[i].Enabled = req.Enabled
		stages[i].Config = string(configJSON)
		if err := h.db.Save(&stages[i]).Error; err != nil {
			return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
		}
		found = true
		break
	}

	if !found {
		insertAt := len(stages)
		for i, stage := range stages {
			if stage.Module == "reverse_proxy" {
				insertAt = i
				break
			}
		}

		newStage := db.PipelineStage{
			ID:      db.NewID(),
			SiteID:  siteID,
			Module:  managedWafModule,
			Enabled: req.Enabled,
			Config:  string(configJSON),
		}

		for i := insertAt; i < len(stages); i++ {
			stages[i].Order++
			_ = h.db.Model(&stages[i]).Update("order", stages[i].Order)
		}

		if insertAt < len(stages) {
			newStage.Order = stages[insertAt].Order - 1
			if newStage.Order < 0 {
				newStage.Order = insertAt
			}
		} else if len(stages) > 0 {
			newStage.Order = stages[len(stages)-1].Order + 1
		}

		if err := h.db.Create(&newStage).Error; err != nil {
			return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
		}
	}

	_ = h.regenerate()

	return c.JSON(http.StatusOK, managedWafResponse{
		Enabled: req.Enabled,
		Config:  req.Config,
	})
}
