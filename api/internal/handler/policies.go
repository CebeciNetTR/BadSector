package handler

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/badsector/badsector/api/internal/db"
	"github.com/labstack/echo/v4"
)

type policyRequest struct {
	Name       string      `json:"name"`
	Priority   int         `json:"priority"`
	Enabled    *bool       `json:"enabled"`
	Conditions interface{} `json:"conditions"`
	Actions    interface{} `json:"actions"`
}

func (h *Handler) listPolicies(c echo.Context) error {
	var policies []db.Policy
	if err := h.db.Where("site_id = ?", c.Param("id")).Order("priority asc").Find(&policies).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, policies)
}

func (h *Handler) createPolicy(c echo.Context) error {
	var req policyRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if err := validatePolicyRequest(req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	conditionsJSON, _ := json.Marshal(req.Conditions)
	actionsJSON, _ := json.Marshal(req.Actions)

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}

	priority := req.Priority
	if priority <= 0 {
		priority = 100
	}

	policy := db.Policy{
		ID:         db.NewID(),
		SiteID:     c.Param("id"),
		Name:       strings.TrimSpace(req.Name),
		Priority:   priority,
		Enabled:    enabled,
		Conditions: string(conditionsJSON),
		Actions:    string(actionsJSON),
	}

	if err := h.db.Create(&policy).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	_ = h.regenerate()
	return c.JSON(http.StatusCreated, policy)
}

func (h *Handler) updatePolicy(c echo.Context) error {
	var policy db.Policy
	if err := h.db.Where("id = ? AND site_id = ?", c.Param("policyId"), c.Param("id")).First(&policy).Error; err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "policy not found")
	}

	var req policyRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	if err := validatePolicyRequest(req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	policy.Name = strings.TrimSpace(req.Name)
	policy.Priority = req.Priority
	if req.Enabled != nil {
		policy.Enabled = *req.Enabled
	}

	conditionsJSON, _ := json.Marshal(req.Conditions)
	actionsJSON, _ := json.Marshal(req.Actions)
	policy.Conditions = string(conditionsJSON)
	policy.Actions = string(actionsJSON)

	if err := h.db.Save(&policy).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	_ = h.regenerate()
	return c.JSON(http.StatusOK, policy)
}

func (h *Handler) deletePolicy(c echo.Context) error {
	result := h.db.Where("id = ? AND site_id = ?", c.Param("policyId"), c.Param("id")).Delete(&db.Policy{})
	if result.Error != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, result.Error.Error())
	}
	if result.RowsAffected == 0 {
		return echo.NewHTTPError(http.StatusNotFound, "policy not found")
	}
	_ = h.regenerate()
	return c.NoContent(http.StatusNoContent)
}

func validatePolicyRequest(req policyRequest) error {
	if strings.TrimSpace(req.Name) == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "name is required")
	}
	if req.Conditions == nil {
		return echo.NewHTTPError(http.StatusBadRequest, "conditions are required")
	}
	if req.Actions == nil {
		return echo.NewHTTPError(http.StatusBadRequest, "actions are required")
	}
	return nil
}
