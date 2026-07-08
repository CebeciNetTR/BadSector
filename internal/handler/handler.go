package handler

import (
	"net/http"
	"strconv"

	"github.com/badsector/badsector/internal/auth"
	"github.com/badsector/badsector/internal/certs"
	"github.com/badsector/badsector/internal/db"
	"github.com/badsector/badsector/internal/metrics"
	"github.com/badsector/badsector/internal/runtime"
	"github.com/badsector/badsector/internal/trace"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

type Handler struct {
	db        *gorm.DB
	generator *runtime.Generator
	reloader  *runtime.EngineReloader
	traces    *trace.Store
	metrics   *metrics.Store
	auth      *auth.Service
	certs     *certs.Manager
}

func New(
	database *gorm.DB,
	generator *runtime.Generator,
	reloader *runtime.EngineReloader,
	traces *trace.Store,
	metricsStore *metrics.Store,
	authService *auth.Service,
	certManager *certs.Manager,
) *Handler {
	return &Handler{
		db:        database,
		generator: generator,
		reloader:  reloader,
		traces:    traces,
		metrics:   metricsStore,
		auth:      authService,
		certs:     certManager,
	}
}

func (h *Handler) Register(g *echo.Group) {
	g.POST("/auth/login", h.login)

	g.GET("/metrics/dashboard", h.dashboardMetrics)

	g.GET("/sites", h.listSites)
	g.POST("/sites", h.createSite)
	g.GET("/sites/:id", h.getSite)
	g.PUT("/sites/:id", h.updateSite)
	g.DELETE("/sites/:id", h.deleteSite)

	g.GET("/sites/:id/policies", h.listPolicies)
	g.POST("/sites/:id/policies", h.createPolicy)
	g.PUT("/sites/:id/policies/:policyId", h.updatePolicy)
	g.DELETE("/sites/:id/policies/:policyId", h.deletePolicy)

	g.GET("/sites/:id/pipeline", h.getPipeline)
	g.PUT("/sites/:id/pipeline", h.updatePipeline)

	g.GET("/sites/:id/rate-limits", h.getRateLimits)
	g.PUT("/sites/:id/rate-limits", h.updateRateLimits)

	g.GET("/sites/:id/managed-waf", h.getManagedWaf)
	g.PUT("/sites/:id/managed-waf", h.updateManagedWaf)

	g.GET("/geoip/status", h.geoipStatus)

	g.GET("/sites/:id/asn", h.getAsn)
	g.PUT("/sites/:id/asn", h.updateAsn)
	g.GET("/sites/:id/geoip", h.getGeoip)
	g.PUT("/sites/:id/geoip", h.updateGeoip)
	g.GET("/sites/:id/header-validation", h.getHeaderValidation)
	g.PUT("/sites/:id/header-validation", h.updateHeaderValidation)
	g.GET("/sites/:id/burst-detection", h.getBurstDetection)
	g.PUT("/sites/:id/burst-detection", h.updateBurstDetection)
	g.GET("/sites/:id/js-challenge", h.getJsChallenge)
	g.PUT("/sites/:id/js-challenge", h.updateJsChallenge)
	g.GET("/sites/:id/cookie-challenge", h.getCookieChallenge)
	g.PUT("/sites/:id/cookie-challenge", h.updateCookieChallenge)
	g.GET("/sites/:id/custom-rules", h.getCustomRules)
	g.GET("/sites/:id/custom-rules/status", h.getCustomRulesStatus)
	g.PUT("/sites/:id/custom-rules", h.updateCustomRules)

	g.GET("/certificates", h.listCertificates)
	g.GET("/sites/:id/certificates", h.listSiteCertificates)
	g.POST("/sites/:id/certificates", h.createSiteCertificate)
	g.GET("/certificates/:certId", h.getCertificate)
	g.POST("/certificates/:certId/issue", h.issueCertificate)
	g.POST("/certificates/:certId/renew", h.renewCertificate)
	g.DELETE("/certificates/:certId", h.deleteCertificate)

	g.GET("/sites/:id/traces", h.listTraces)

	g.POST("/runtime/reload", h.reloadRuntime)
}

func (h *Handler) regenerate() error {
	if err := h.generator.GenerateAll(h.db); err != nil {
		return err
	}
	if h.reloader != nil {
		if err := h.reloader.Reload(); err != nil {
			return err
		}
	}
	return nil
}

func (h *Handler) login(c echo.Context) error {
	var req auth.LoginRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	resp, err := h.auth.Login(req.Username, req.Password)
	if err != nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "invalid credentials")
	}

	return c.JSON(http.StatusOK, resp)
}

func (h *Handler) listTraces(c echo.Context) error {
	siteID := c.Param("id")

	var site db.Site
	if err := h.db.First(&site, "id = ?", siteID).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "site not found")
	}

	limit := 50
	if raw := c.QueryParam("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			limit = n
		}
	}

	if h.traces == nil {
		return c.JSON(http.StatusOK, []trace.RequestTrace{})
	}

	traces, err := h.traces.List(siteID, limit)
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusOK, traces)
}

func (h *Handler) reloadRuntime(c echo.Context) error {
	if err := h.regenerate(); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, map[string]string{"status": "reloaded"})
}
