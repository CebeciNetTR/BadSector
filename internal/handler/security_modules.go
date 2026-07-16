package handler

import "github.com/labstack/echo/v4"

func DefaultAsnConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":        true,
		"database_path":  "/etc/badsector/geoip/GeoLite2-ASN.mmdb",
		"block_asns":     []interface{}{},
		"allow_asns":     []interface{}{},
		"allow_only":     false,
		"ip_map":         map[string]interface{}{},
		"fail_open":      true,
	}
}

func DefaultGeoipConfig() map[string]interface{} {
	return map[string]interface{}{
		"database_path":       "/etc/badsector/geoip/GeoLite2-Country.mmdb",
		"fail_open":           true,
		"block_countries":     []interface{}{},
		"allow_countries":     []interface{}{},
		"allow_only":          false,
		"use_header_fallback": true,
	}
}

func DefaultHeaderValidationConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":   true,
		"required":  []interface{}{},
		"forbidden": []interface{}{},
		"rules":     []interface{}{},
	}
}

func DefaultBurstDetectionConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":   true,
		"window":    10,
		"threshold": 50,
		"key_by":    "ip",
		"paths":     []interface{}{"/*"},
		"action":    "rate_limit",
		"fail_open": true,
	}
}

func DefaultJsChallengeConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":       false,
		"paths":         []interface{}{"/*"},
		"exclude_paths": []interface{}{"/badsector/*"},
		// Imzali Proof-of-Work parametreleri (stateless HMAC).
		"pass_cookie":       "bs_pass",
		"pow_cookie":        "bs_pow",
		"difficulty":        4, // normal (basta hex sifir sayisi ~ 2^16 hash)
		"difficulty_attack": 5, // attack mode'da otomatik yukselir (~2^20 hash)
		"pass_ttl":          3600,
		"ban_threshold":     3,
		"ban_ttl":           86400,
		// Ozel challenge HTML sablonu (bos ise engine varsayilanini kullanir).
		// PoW cozucu <script> her zaman engine tarafindan enjekte edilir.
		"template": "",
	}
}

func DefaultCookieChallengeConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":       false,
		"paths":         []interface{}{"/*"},
		"exclude_paths": []interface{}{"/badsector/*"},
		"cookie_name":   "bs_verified",
		"cookie_ttl":    86400,
	}
}

func DefaultCustomRulesConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":   true,
		"fail_open": true,
		"rules":     []interface{}{},
	}
}

func (h *Handler) getCustomRules(c echo.Context) error {
	return h.getModuleStage(c, "custom_rules", DefaultCustomRulesConfig)
}

func (h *Handler) updateCustomRules(c echo.Context) error {
	return h.updateModuleStage(c, "custom_rules", DefaultCustomRulesConfig)
}

func (h *Handler) getAsn(c echo.Context) error {
	return h.getModuleStage(c, "asn", DefaultAsnConfig)
}

func (h *Handler) updateAsn(c echo.Context) error {
	return h.updateModuleStage(c, "asn", DefaultAsnConfig)
}

func (h *Handler) getGeoip(c echo.Context) error {
	return h.getModuleStage(c, "geoip", DefaultGeoipConfig)
}

func (h *Handler) updateGeoip(c echo.Context) error {
	return h.updateModuleStage(c, "geoip", DefaultGeoipConfig)
}

func (h *Handler) getHeaderValidation(c echo.Context) error {
	return h.getModuleStage(c, "header_validation", DefaultHeaderValidationConfig)
}

func (h *Handler) updateHeaderValidation(c echo.Context) error {
	return h.updateModuleStage(c, "header_validation", DefaultHeaderValidationConfig)
}

func (h *Handler) getBurstDetection(c echo.Context) error {
	return h.getModuleStage(c, "burst_detection", DefaultBurstDetectionConfig)
}

func (h *Handler) updateBurstDetection(c echo.Context) error {
	return h.updateModuleStage(c, "burst_detection", DefaultBurstDetectionConfig)
}

func (h *Handler) getJsChallenge(c echo.Context) error {
	return h.getModuleStage(c, "js_challenge", DefaultJsChallengeConfig)
}

func (h *Handler) updateJsChallenge(c echo.Context) error {
	return h.updateModuleStage(c, "js_challenge", DefaultJsChallengeConfig)
}

func (h *Handler) getCookieChallenge(c echo.Context) error {
	return h.getModuleStage(c, "cookie_challenge", DefaultCookieChallengeConfig)
}

func (h *Handler) updateCookieChallenge(c echo.Context) error {
	return h.updateModuleStage(c, "cookie_challenge", DefaultCookieChallengeConfig)
}
