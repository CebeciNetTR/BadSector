package handler

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type AttackModeRequest struct {
	Enabled bool `json:"enabled"`
}

func (h *Handler) getAttackMode(c echo.Context) error {
	if h.traces == nil {
		return c.JSON(http.StatusOK, map[string]interface{}{"enabled": false})
	}
	enabled, err := h.traces.GetAttackMode()
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"enabled": enabled})
}

func (h *Handler) updateAttackMode(c echo.Context) error {
	if h.traces == nil {
		return echo.NewHTTPError(http.StatusBadRequest, "redis trace store not configured")
	}
	var req AttackModeRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	if err := h.traces.SetAttackMode(req.Enabled); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"enabled": req.Enabled})
}
