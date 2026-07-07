package handler

import (
	"net/http"
	"strings"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

type createCertificateRequest struct {
	Domain    string `json:"domain"`
	Email     string `json:"email"`
	AutoRenew *bool  `json:"auto_renew"`
	Issue     bool   `json:"issue"`
}

func (h *Handler) listCertificates(c echo.Context) error {
	var items []db.Certificate
	q := h.db.Order("created_at desc")
	if siteID := c.QueryParam("site_id"); siteID != "" {
		q = q.Where("site_id = ?", siteID)
	}
	if err := q.Find(&items).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, items)
}

func (h *Handler) listSiteCertificates(c echo.Context) error {
	siteID := c.Param("id")
	if err := h.db.First(&db.Site{}, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var items []db.Certificate
	if err := h.db.Where("site_id = ?", siteID).Order("created_at desc").Find(&items).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, items)
}

func (h *Handler) createSiteCertificate(c echo.Context) error {
	if h.certs == nil {
		return echo.NewHTTPError(http.StatusServiceUnavailable, "certificate manager not configured")
	}

	siteID := c.Param("id")
	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var req createCertificateRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	domain := strings.ToLower(strings.TrimSpace(req.Domain))
	if domain == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "domain is required")
	}

	autoRenew := true
	if req.AutoRenew != nil {
		autoRenew = *req.AutoRenew
	}

	record := db.Certificate{
		ID:        db.NewID(),
		SiteID:    siteID,
		Domain:    domain,
		Email:     strings.TrimSpace(req.Email),
		Status:    db.CertStatusPending,
		AutoRenew: autoRenew,
	}

	if err := h.db.Create(&record).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	if req.Issue {
		if err := h.certs.Issue(c.Request().Context(), record.ID); err != nil {
			_ = h.db.First(&record, "id = ?", record.ID)
			return c.JSON(http.StatusAccepted, map[string]interface{}{
				"certificate": record,
				"error":         err.Error(),
			})
		}
		_ = h.db.First(&record, "id = ?", record.ID)
	}

	return c.JSON(http.StatusCreated, record)
}

func (h *Handler) getCertificate(c echo.Context) error {
	var record db.Certificate
	if err := h.db.First(&record, "id = ?", c.Param("certId")).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "certificate not found")
	}
	return c.JSON(http.StatusOK, record)
}

func (h *Handler) issueCertificate(c echo.Context) error {
	if h.certs == nil {
		return echo.NewHTTPError(http.StatusServiceUnavailable, "certificate manager not configured")
	}

	certID := c.Param("certId")
	if err := h.certs.Issue(c.Request().Context(), certID); err != nil {
		var record db.Certificate
		_ = h.db.First(&record, "id = ?", certID)
		return c.JSON(http.StatusBadRequest, map[string]interface{}{
			"error":       err.Error(),
			"certificate": record,
		})
	}

	var record db.Certificate
	_ = h.db.First(&record, "id = ?", certID)
	return c.JSON(http.StatusOK, record)
}

func (h *Handler) renewCertificate(c echo.Context) error {
	if h.certs == nil {
		return echo.NewHTTPError(http.StatusServiceUnavailable, "certificate manager not configured")
	}

	certID := c.Param("certId")
	if err := h.certs.Renew(c.Request().Context(), certID); err != nil {
		var record db.Certificate
		_ = h.db.First(&record, "id = ?", certID)
		return c.JSON(http.StatusBadRequest, map[string]interface{}{
			"error":       err.Error(),
			"certificate": record,
		})
	}

	var record db.Certificate
	_ = h.db.First(&record, "id = ?", certID)
	return c.JSON(http.StatusOK, record)
}

func (h *Handler) deleteCertificate(c echo.Context) error {
	certID := c.Param("certId")
	var record db.Certificate
	if err := h.db.First(&record, "id = ?", certID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "certificate not found")
	}

	if h.certs != nil {
		_ = h.certs.DeleteFiles(record.Domain)
	}

	if err := h.db.Delete(&record).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}
