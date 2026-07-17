package handler

import (
	"encoding/json"
	"testing"
)

func TestMergeStageConfigPreservesExisting(t *testing.T) {
	existing := `{"allow_only":true,"allow_countries":["TR"],"fail_open":true}`
	incoming := `{"allow_only":false,"allow_countries":[],"fail_open":true}`

	got := mergeStageConfig("geoip", incoming, existing)
	if got != existing {
		t.Fatalf("expected existing geoip config preserved, got %s", got)
	}
}

func TestMergeStageConfigPreservesCustomRules(t *testing.T) {
	existing := `{"enabled":true,"fail_open":true,"rules":[{"id":"r1","match":{"expr":"path contains \"wp\""},"action":{"type":"block","status":403}}]}`
	incoming := `{"enabled":true,"fail_open":true,"rules":[]}`

	got := mergeStageConfig("custom_rules", incoming, existing)
	if got != existing {
		t.Fatalf("expected existing rules preserved, got %s", got)
	}
}

func TestMergeStageConfigUsesIncomingWhenNoExisting(t *testing.T) {
	incoming := `{"enabled":true,"fail_open":true,"rules":[{"id":"r2"}]}`

	got := mergeStageConfig("custom_rules", incoming, "")
	if got != incoming {
		t.Fatalf("expected incoming config, got %s", got)
	}
}

func TestSyncConfigEnabled(t *testing.T) {
	in := `{"enabled":true,"fail_open":true,"rules":[]}`
	got := syncConfigEnabled(in, false)
	var cfg map[string]interface{}
	if err := json.Unmarshal([]byte(got), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg["enabled"] != false {
		t.Fatalf("expected enabled=false, got %v", cfg["enabled"])
	}
}
