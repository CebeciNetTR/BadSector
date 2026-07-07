package handler

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"github.com/badsector/badsector/internal/db"
	"github.com/labstack/echo/v4"
)

type siteRequest struct {
	Name       string                 `json:"name"`
	Hosts      []string               `json:"hosts"`
	Settings   map[string]interface{} `json:"settings"`
	Enabled    *bool                  `json:"enabled"`
	BackendURL string                 `json:"backend_url"`
}

func (h *Handler) listSites(c echo.Context) error {
	var sites []db.Site
	if err := h.db.Find(&sites).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, sites)
}

func (h *Handler) createSite(c echo.Context) error {
	var req siteRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "name is required")
	}
	if len(normalizeHosts(req.Hosts)) == 0 {
		return echo.NewHTTPError(http.StatusBadRequest, "at least one host is required")
	}

	backendURL := normalizeBackendURL(req.BackendURL)
	if backendURL == "" {
		backendURL = db.DefaultBackendURL()
	}

	settings := req.Settings
	if settings == nil {
		settings = map[string]interface{}{}
	}

	settingsJSON, _ := json.Marshal(settings)
	hostsJSON, _ := json.Marshal(normalizeHosts(req.Hosts))

	site := db.Site{
		ID:       db.NewID(),
		Name:     req.Name,
		Hosts:    string(hostsJSON),
		Settings: string(settingsJSON),
		Enabled:  true,
	}

	if req.Enabled != nil {
		site.Enabled = *req.Enabled
	}

	if err := h.db.Create(&site).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	stages := db.DefaultPipelineStages(site.ID)
	if backendURL != db.DefaultBackendURL() {
		proxyConfig, _ := json.Marshal(map[string]interface{}{
			"upstream":    "backend",
			"backend_url": backendURL,
		})
		for i := range stages {
			if stages[i].Module == "reverse_proxy" {
				stages[i].Config = string(proxyConfig)
			}
		}
	}

	if err := h.db.Create(&stages).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	_ = h.regenerate()
	return c.JSON(http.StatusCreated, site)
}

func (h *Handler) getSite(c echo.Context) error {
	var site db.Site
	if err := h.db.Preload("Policies").Preload("Pipeline").First(&site, "id = ?", c.Param("id")).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}
	return c.JSON(http.StatusOK, site)
}

func (h *Handler) updateSite(c echo.Context) error {
	var site db.Site
	if err := h.db.First(&site, "id = ?", c.Param("id")).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	var req siteRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if req.Name != "" {
		site.Name = strings.TrimSpace(req.Name)
	}
	if req.Hosts != nil {
		hosts := normalizeHosts(req.Hosts)
		if len(hosts) == 0 {
			return echo.NewHTTPError(http.StatusBadRequest, "at least one host is required")
		}
		hostsJSON, _ := json.Marshal(hosts)
		site.Hosts = string(hostsJSON)
	}
	if req.Settings != nil {
		settingsJSON, _ := json.Marshal(req.Settings)
		site.Settings = string(settingsJSON)
	}
	if req.Enabled != nil {
		site.Enabled = *req.Enabled
	}

	if err := h.db.Save(&site).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	if req.BackendURL != "" {
		backendURL := normalizeBackendURL(req.BackendURL)
		if backendURL == "" {
			return echo.NewHTTPError(http.StatusBadRequest, "invalid backend_url")
		}
		if err := db.SetBackendURL(h.db, site.ID, backendURL); err != nil {
			return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
		}
	}

	_ = h.regenerate()
	return c.JSON(http.StatusOK, site)
}

func (h *Handler) deleteSite(c echo.Context) error {
	siteID := c.Param("id")

	if err := h.db.Where("site_id = ?", siteID).Delete(&db.PipelineStage{}).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if err := h.db.Where("site_id = ?", siteID).Delete(&db.Policy{}).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if err := h.db.Delete(&db.Site{}, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	_ = h.regenerate()
	return c.NoContent(http.StatusNoContent)
}

func normalizeHosts(hosts []string) []string {
	out := make([]string, 0, len(hosts))
	seen := map[string]bool{}
	for _, h := range hosts {
		h = strings.TrimSpace(strings.ToLower(h))
		if h == "" || seen[h] {
			continue
		}
		seen[h] = true
		out = append(out, h)
	}
	return out
}

func normalizeBackendURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}
