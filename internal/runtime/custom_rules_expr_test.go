package runtime

import (
	"strings"
	"testing"
)

func TestBuildExprFromBuilder_OR(t *testing.T) {
	builder := map[string]interface{}{
		"logic": "or",
		"conditions": []interface{}{
			map[string]interface{}{
				"field":    "path",
				"operator": "contains",
				"value":    ".env",
			},
			map[string]interface{}{
				"field":    "path",
				"operator": "contains",
				"value":    "wp",
			},
		},
	}

	got := buildExprFromBuilder(builder)
	want := `path contains ".env" or path contains "wp"`
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestEnsureCustomRuleExprsFromBuilder(t *testing.T) {
	cfg := map[string]interface{}{
		"rules": []interface{}{
			map[string]interface{}{
				"id":   "r1",
				"name": "test",
				"match": map[string]interface{}{
					"_builder": map[string]interface{}{
						"logic": "or",
						"conditions": []interface{}{
							map[string]interface{}{
								"field":    "path",
								"operator": "contains",
								"value":    "wp",
							},
						},
					},
				},
			},
		},
	}

	EnsureCustomRulesConfig(cfg)

	rules := cfg["rules"].([]interface{})
	rule := rules[0].(map[string]interface{})
	match := rule["match"].(map[string]interface{})
	if match["expr"] != `path contains "wp"` {
		t.Fatalf("expr not built: %#v", match["expr"])
	}
	if _, ok := match["_builder"]; ok {
		t.Fatal("_builder should be stripped")
	}
}

func TestEnsureCustomRuleExprs_PreservesValidExpr(t *testing.T) {
	cfg := map[string]interface{}{
		"rules": []interface{}{
			map[string]interface{}{
				"match": map[string]interface{}{
					"expr": `path contains ".env" or path contains "wp"`,
				},
			},
		},
	}
	EnsureCustomRulesConfig(cfg)
	rules := cfg["rules"].([]interface{})
	match := rules[0].(map[string]interface{})["match"].(map[string]interface{})
	if !strings.Contains(match["expr"].(string), "wp") {
		t.Fatalf("expr altered unexpectedly: %#v", match["expr"])
	}
}
