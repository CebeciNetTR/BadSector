package runtime

import (
	"fmt"
	"strings"
)

// buildExprFromBuilder mirrors ui/src/lib/customRuleExpr.ts so runtime always has expr
// even when the panel saved only _builder (UI-only field stripped before engine).
func buildExprFromBuilder(builder map[string]interface{}) string {
	if builder == nil {
		return ""
	}

	logic, _ := builder["logic"].(string)
	if logic == "" {
		logic = "and"
	}

	rawConds, _ := builder["conditions"].([]interface{})
	parts := make([]string, 0, len(rawConds))
	for _, raw := range rawConds {
		cond, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		if part := conditionToExpr(cond); part != "" {
			parts = append(parts, part)
		}
	}

	if len(parts) == 0 {
		return "false"
	}
	if len(parts) == 1 {
		return parts[0]
	}

	sep := " and "
	if logic == "or" {
		sep = " or "
	}
	return strings.Join(parts, sep)
}

func conditionToExpr(c map[string]interface{}) string {
	field, _ := c["field"].(string)
	op, _ := c["operator"].(string)
	value, _ := c["value"].(string)
	headerName, _ := c["headerName"].(string)

	f := field
	if field == "header" {
		name := strings.TrimSpace(headerName)
		if name == "" {
			name = "X-Custom"
		}
		f = "header." + name
	} else if field == "ua" {
		f = "ua"
	}

	value = strings.TrimSpace(value)
	escaped := escapeExprString(value)

	switch op {
	case "is_true":
		return fmt.Sprintf("%s == true", f)
	case "is_false":
		return fmt.Sprintf("%s != true", f)
	case "equals":
		if value == "" && field != "trusted_bot" {
			return ""
		}
		return fmt.Sprintf(`%s == "%s"`, f, escaped)
	case "not_equals":
		if value == "" {
			return ""
		}
		return fmt.Sprintf(`%s != "%s"`, f, escaped)
	case "contains":
		if value == "" {
			return ""
		}
		if field == "path" || field == "ua" || field == "host" || field == "header" {
			return fmt.Sprintf(`%s contains "%s"`, f, escaped)
		}
		return fmt.Sprintf(`%s.contains("%s")`, f, escaped)
	case "not_contains":
		if value == "" {
			return ""
		}
		return fmt.Sprintf(`not (%s contains "%s")`, f, escaped)
	case "starts_with":
		if value == "" {
			return ""
		}
		return fmt.Sprintf(`%s.starts_with("%s")`, f, escaped)
	case "not_starts_with":
		if value == "" {
			return ""
		}
		return fmt.Sprintf(`not (%s.starts_with("%s"))`, f, escaped)
	case "matches":
		if value == "" {
			return ""
		}
		return fmt.Sprintf(`%s.matches("%s")`, f, escaped)
	case "in_list":
		items := parseListValue(value)
		if len(items) == 0 {
			return ""
		}
		return fmt.Sprintf("%s in %s", f, formatExprList(items))
	case "not_in_list":
		items := parseListValue(value)
		if len(items) == 0 {
			return ""
		}
		return fmt.Sprintf("%s not in %s", f, formatExprList(items))
	default:
		return ""
	}
}

func escapeExprString(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}

func parseListValue(raw string) []string {
	raw = strings.ReplaceAll(raw, "\n", ",")
	raw = strings.ReplaceAll(raw, ";", ",")
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		p = strings.Trim(p, `"'`)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func formatExprList(items []string) string {
	quoted := make([]string, len(items))
	for i, item := range items {
		quoted[i] = `"` + escapeExprString(item) + `"`
	}
	return "[" + strings.Join(quoted, ", ") + "]"
}

func ensureCustomRuleExprs(cfg map[string]interface{}) {
	rawRules, ok := cfg["rules"].([]interface{})
	if !ok {
		return
	}

	for _, raw := range rawRules {
		rule, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		match, ok := rule["match"].(map[string]interface{})
		if !ok {
			continue
		}

		expr, _ := match["expr"].(string)
		expr = strings.TrimSpace(expr)
		if expr != "" && expr != "false" && expr != `path contains ""` {
			match["expr"] = expr
			delete(match, "_builder")
			continue
		}

		if builder, ok := match["_builder"].(map[string]interface{}); ok {
			if built := strings.TrimSpace(buildExprFromBuilder(builder)); built != "" && built != "false" {
				match["expr"] = built
			}
		}

		delete(match, "_builder")
	}
}

// EnsureCustomRulesConfig fills missing match.expr from _builder and strips UI-only fields.
func EnsureCustomRulesConfig(cfg map[string]interface{}) {
	ensureCustomRuleExprs(cfg)
}
