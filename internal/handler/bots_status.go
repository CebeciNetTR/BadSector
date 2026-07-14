package handler

import (
	"net/http"

	"github.com/badsector/badsector/internal/bots"
	"github.com/badsector/badsector/internal/config"
	"github.com/labstack/echo/v4"
)

// botsStatus, worker'in yazdigi bot IP aralik dosyasinin durumunu dondurur
// (son guncelleme zamani, kaynak durumlari ve bot basina aralik sayilari).
func (h *Handler) botsStatus(c echo.Context) error {
	cfg := config.Load()
	syncer := bots.NewSyncer(cfg.BotsDataPath)
	return c.JSON(http.StatusOK, syncer.Status())
}
