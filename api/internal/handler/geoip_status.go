package handler

import (
	"net/http"

	"github.com/badsector/badsector/api/internal/config"
	"github.com/badsector/badsector/api/internal/geoip"
	"github.com/labstack/echo/v4"
)

func (h *Handler) geoipStatus(c echo.Context) error {
	cfg := config.Load()
	syncer := geoip.NewSyncer(cfg.MaxMindLicenseKey, cfg.GeoIPDataPath)
	return c.JSON(http.StatusOK, syncer.Status())
}
