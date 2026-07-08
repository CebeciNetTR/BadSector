package handler

import (
	"encoding/json"
	"net/http"

	"github.com/badsector/badsector/internal/db"
	"github.com/badsector/badsector/internal/runtime"
	"github.com/labstack/echo/v4"
)

type moduleStageResponse struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

type updateModuleStageRequest struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func (h *Handler) getModuleStage(c echo.Context, module string, defaultConfig func() map[string]interface{}) error {
	siteID := c.Param("id")

	if err := h.db.First(&db.Site{}, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var stages []db.PipelineStage
	if err := h.db.Where("site_id = ?", siteID).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	for _, stage := range stages {
		if stage.Module != module {
			continue
		}
		cfg := defaultConfig()
		if stage.Config != "" {
			_ = json.Unmarshal([]byte(stage.Config), &cfg)
		}
		if module == "custom_rules" {
			runtime.EnsureCustomRulesConfig(cfg)
		}
		return c.JSON(http.StatusOK, moduleStageResponse{
			Enabled: stage.Enabled,
			Config:  cfg,
		})
	}

	return c.JSON(http.StatusOK, moduleStageResponse{
		Enabled: false,
		Config:  defaultConfig(),
	})
}

func (h *Handler) updateModuleStage(c echo.Context, module string, defaultConfig func() map[string]interface{}) error {
	siteID := c.Param("id")

	if err := h.db.First(&db.Site{}, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var req updateModuleStageRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if req.Config == nil {
		req.Config = defaultConfig()
	}
	req.Config["enabled"] = req.Enabled

	if module == "custom_rules" {
		runtime.EnsureCustomRulesConfig(req.Config)
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
		if stages[i].Module != module {
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
			Module:  module,
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

	if err := db.NormalizePipelineOrder(h.db, siteID); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	if err := h.regenerate(); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, "runtime reload failed: "+err.Error())
	}

	return c.JSON(http.StatusOK, moduleStageResponse{
		Enabled: req.Enabled,
		Config:  req.Config,
	})
}
