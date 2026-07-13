package handler

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func (h *Handler) dashboardMetrics(c echo.Context) error {
	if h.metrics == nil {
		return c.JSON(http.StatusOK, map[string]interface{}{
			"requests_total": 0,
			"blocked":        0,
			"challenged":     0,
			"rate_limited":   0,
			"allowed":        0,
			"banned_ips":     0,
			"watched_ips":    0,
			"active_sites":   0,
			"decisions":      map[string]int{},
			"edge": map[string]string{
				"api":    "ok",
				"engine": "unknown",
				"redis":  "unknown",
			},
		})
	}

	data, err := h.metrics.Dashboard(c.Request().Context(), h.db)
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	data.Edge.API = "ok"
	return c.JSON(http.StatusOK, data)
}
