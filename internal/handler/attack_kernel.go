package handler

import (
	"encoding/json"
	"sort"
	"strconv"
	"strings"

	"github.com/badsector/badsector/internal/db"
)

// refreshAttackKernelPolicy aggregates geoip/asn attack lists from all enabled
// pipeline stages and writes Redis keys consumed by deploy/watcher (iptables/ipset
// BEFORE HAProxy — kernel drop).
func (h *Handler) refreshAttackKernelPolicy() error {
	if h.traces == nil {
		return nil
	}

	var stages []db.PipelineStage
	if err := h.db.Where("module IN ? AND enabled = ?", []string{"geoip", "asn"}, true).Find(&stages).Error; err != nil {
		return err
	}

	countrySet := map[string]struct{}{}
	asnSet := map[string]struct{}{}
	exemptSet := map[string]struct{}{}

	for _, stage := range stages {
		cfg := map[string]interface{}{}
		if stage.Config != "" {
			_ = json.Unmarshal([]byte(stage.Config), &cfg)
		}
		switch stage.Module {
		case "geoip":
			for _, cc := range configStringList(cfg, "attack_block_countries") {
				countrySet[strings.ToUpper(cc)] = struct{}{}
			}
			for _, cc := range configStringList(cfg, "block_countries") {
				countrySet[strings.ToUpper(cc)] = struct{}{}
			}
			for _, cc := range configStringList(cfg, "allow_countries") {
				exemptSet[strings.ToUpper(cc)] = struct{}{}
			}
		case "asn":
			for _, n := range configIntList(cfg, "attack_block_asns") {
				asnSet[strconv.Itoa(n)] = struct{}{}
			}
		}
	}

	// Yanlislikla block listesine TR yazilsa bile kernel'de dusmesin.
	exemptSet["TR"] = struct{}{}

	return h.traces.SetAttackKernelPolicy(
		joinSortedKeys(countrySet),
		joinSortedKeys(asnSet),
		joinSortedKeys(exemptSet),
	)
}

func configStringList(cfg map[string]interface{}, key string) []string {
	raw, ok := cfg[key]
	if !ok || raw == nil {
		return nil
	}
	switch v := raw.(type) {
	case []string:
		return v
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok && s != "" {
				out = append(out, s)
			}
		}
		return out
	default:
		return nil
	}
}

func configIntList(cfg map[string]interface{}, key string) []int {
	raw, ok := cfg[key]
	if !ok || raw == nil {
		return nil
	}
	switch v := raw.(type) {
	case []int:
		return v
	case []interface{}:
		out := make([]int, 0, len(v))
		for _, item := range v {
			switch n := item.(type) {
			case float64:
				out = append(out, int(n))
			case int:
				out = append(out, n)
			case json.Number:
				if i, err := n.Int64(); err == nil {
					out = append(out, int(i))
				}
			case string:
				if i, err := strconv.Atoi(strings.TrimSpace(n)); err == nil {
					out = append(out, i)
				}
			}
		}
		return out
	default:
		return nil
	}
}

func joinSortedKeys(set map[string]struct{}) string {
	if len(set) == 0 {
		return ""
	}
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return strings.Join(keys, ",")
}
