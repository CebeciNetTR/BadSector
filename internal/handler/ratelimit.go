package handler

import (
	"encoding/json"
	"net/http"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

const rateLimiterModule = "rate_limiter"

// DefaultRateLimitConfig returns sensible defaults for new sites.
func DefaultRateLimitConfig() map[string]interface{} {
	return map[string]interface{}{
		"use_redis": true,
		"fail_mode": "open",
		"redis": map[string]interface{}{
			"host":    "redis",
			"port":    6379,
			"timeout": 100,
		},
		"rules": []interface{}{},
	}
}

type rateLimitResponse struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func (h *Handler) getRateLimits(c echo.Context) error {
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
		if stage.Module != rateLimiterModule {
			continue
		}

		cfg := DefaultRateLimitConfig()
		if stage.Config != "" {
			_ = json.Unmarshal([]byte(stage.Config), &cfg)
		}

		return c.JSON(http.StatusOK, rateLimitResponse{
			Enabled: stage.Enabled,
			Config:  cfg,
		})
	}

	return c.JSON(http.StatusOK, rateLimitResponse{
		Enabled: true,
		Config:  DefaultRateLimitConfig(),
	})
}

type updateRateLimitRequest struct {
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

func (h *Handler) updateRateLimits(c echo.Context) error {
	siteID := c.Param("id")

	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var req updateRateLimitRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if req.Config == nil {
		req.Config = DefaultRateLimitConfig()
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
		if stages[i].Module == rateLimiterModule {
			stages[i].Enabled = req.Enabled
			stages[i].Config = string(configJSON)
			if err := h.db.Save(&stages[i]).Error; err != nil {
				return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
			}
			found = true
			break
		}
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
			Module:  rateLimiterModule,
			Enabled: req.Enabled,
			Config:  string(configJSON),
		}

		for i := insertAt; i < len(stages); i++ {
			stages[i].Order++
			if err := h.db.Model(&stages[i]).Update("order", stages[i].Order).Error; err != nil {
				return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
			}
		}

		if len(stages) == 0 {
			newStage.Order = 0
		} else if insertAt < len(stages) {
			newStage.Order = stages[insertAt].Order - 1
			if newStage.Order < 0 {
				newStage.Order = insertAt
			}
		} else {
			newStage.Order = stages[len(stages)-1].Order + 1
		}

		if err := h.db.Create(&newStage).Error; err != nil {
			return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
		}
	}

	_ = h.regenerate()

	return c.JSON(http.StatusOK, rateLimitResponse{
		Enabled: req.Enabled,
		Config:  req.Config,
	})
}
