package handler

import "testing"

func TestMergeStageConfigPreservesCustomRules(t *testing.T) {
	existing := `{"enabled":true,"fail_open":true,"rules":[{"id":"r1","match":{"expr":"path contains \"wp\""},"action":{"type":"block","status":403}}]}`
	incoming := `{"enabled":true,"fail_open":true,"rules":[]}`

	got := mergeStageConfig("custom_rules", incoming, existing)
	if got != existing {
		t.Fatalf("expected existing rules preserved, got %s", got)
	}
}

func TestMergeStageConfigUsesIncomingWhenRulesPresent(t *testing.T) {
	existing := `{"enabled":true,"fail_open":true,"rules":[]}`
	incoming := `{"enabled":true,"fail_open":true,"rules":[{"id":"r2","match":{"expr":"path contains \"wp\""},"action":{"type":"block"}}]}`

	got := mergeStageConfig("custom_rules", incoming, existing)
	if got != incoming {
		t.Fatalf("expected incoming config, got %s", got)
	}
}
