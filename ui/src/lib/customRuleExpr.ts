import {
  defaultBuilderState,
  type CustomRuleBuilderState,
  type RuleField,
  type VisualCondition,
} from '../types/customRuleBuilder'
import type { CustomRule, CustomRuleMatch } from '../types/securityModules'

function escapeString(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
}

function fieldRef(c: VisualCondition): string {
  if (c.field === 'header') {
    const name = (c.headerName ?? '').trim() || 'X-Custom'
    return `header.${name}`
  }
  if (c.field === 'ua') return 'ua'
  return c.field
}

function parseListValue(raw: string): string[] {
  return raw
    .split(/[,;\n]+/)
    .map((s) => s.trim().replace(/^["']|["']$/g, ''))
    .filter(Boolean)
}

function formatList(items: string[]): string {
  return `[${items.map((i) => `"${escapeString(i)}"`).join(', ')}]`
}

export function buildExpr(state: CustomRuleBuilderState): string {
  const parts = state.conditions
    .map((c) => conditionToExpr(c))
    .filter((p): p is string => Boolean(p))

  if (parts.length === 0) return 'false'
  if (parts.length === 1) return parts[0]
  return parts.join(state.logic === 'or' ? ' or ' : ' and ')
}

function conditionToExpr(c: VisualCondition): string | null {
  const f = fieldRef(c)
  const v = c.value.trim()

  switch (c.operator) {
    case 'is_true':
      return `${f} == true`
    case 'is_false':
      return `${f} != true`
    case 'equals':
      if (!v && c.field !== 'trusted_bot') return null
      return `${f} == "${escapeString(v)}"`
    case 'not_equals':
      if (!v) return null
      return `${f} != "${escapeString(v)}"`
    case 'contains':
      if (!v) return null
      if (c.field === 'path' || c.field === 'ua' || c.field === 'host' || c.field === 'header') {
        return `${f} contains "${escapeString(v)}"`
      }
      return `${f}.contains("${escapeString(v)}")`
    case 'not_contains':
      if (!v) return null
      return `not (${f} contains "${escapeString(v)}")`
    case 'starts_with':
      if (!v) return null
      return `${f}.starts_with("${escapeString(v)}")`
    case 'not_starts_with':
      if (!v) return null
      return `not (${f}.starts_with("${escapeString(v)}"))`
    case 'matches':
      if (!v) return null
      return `${f}.matches("${escapeString(v)}")`
    case 'in_list': {
      const items = parseListValue(v)
      if (items.length === 0) return null
      return `${f} in ${formatList(items)}`
    }
    case 'not_in_list': {
      const items = parseListValue(v)
      if (items.length === 0) return null
      return `${f} not in ${formatList(items)}`
    }
    default:
      return null
  }
}

/** Best-effort parse for loading existing rules into the visual builder. */
export function tryParseBuilder(expr: string): CustomRuleBuilderState | null {
  if (!expr || !expr.trim()) return null

  const trimmed = expr.trim()
  let logic: 'and' | 'or' = 'and'
  let parts: string[] = []

  if (/\s+or\s+/i.test(trimmed)) {
    logic = 'or'
    parts = splitTopLevel(trimmed, ' or ')
  } else {
    parts = splitTopLevel(trimmed, ' and ')
  }

  const conditions: VisualCondition[] = []
  for (const part of parts) {
    const c = parseAtom(part.trim())
    if (c) conditions.push(c)
  }

  if (conditions.length === 0) return null
  return { logic, conditions }
}

function splitTopLevel(s: string, sep: string): string[] {
  const out: string[] = []
  let depth = 0
  let start = 0
  const sl = sep.length
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '(') depth++
    else if (s[i] === ')') depth--
    else if (depth === 0 && s.slice(i, i + sl).toLowerCase() === sep) {
      out.push(s.slice(start, i))
      i += sl - 1
      start = i + 1
    }
  }
  out.push(s.slice(start))
  return out.filter(Boolean)
}

function parseAtom(atom: string): VisualCondition | null {
  let inner = atom
  if (inner.startsWith('not (') && inner.endsWith(')')) {
    inner = inner.slice(5, -1).trim()
    const c = parseAtomPositive(inner)
    if (!c) return null
    if (c.operator === 'contains') return { ...c, operator: 'not_contains' }
    if (c.operator === 'starts_with') return { ...c, operator: 'not_starts_with' }
    return null
  }
  return parseAtomPositive(atom)
}

function parseAtomPositive(atom: string): VisualCondition | null {
  const id = `c-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`

  let m = atom.match(/^([\w.]+)\s*==\s*true$/)
  if (m) return { id, field: mapField(m[1]), operator: 'is_true', value: '' }

  m = atom.match(/^([\w.]+)\s*!=\s*true$/)
  if (m) return { id, field: mapField(m[1]), operator: 'is_false', value: '' }

  m = atom.match(/^([\w.]+)\s+in\s+\[(.+)\]$/)
  if (m) return { id, field: mapField(m[1]), operator: 'in_list', value: m[2].replace(/"/g, '').replace(/\s*,\s*/g, ', ') }

  m = atom.match(/^([\w.]+)\s+not\s+in\s+\[(.+)\]$/)
  if (m) return { id, field: mapField(m[1]), operator: 'not_in_list', value: m[2].replace(/"/g, '').replace(/\s*,\s*/g, ', ') }

  m = atom.match(/^([\w.]+)\s+contains\s+"((?:\\.|[^"\\])*)"$/)
  if (m) return { id, ...splitField(m[1]), operator: 'contains', value: unescape(m[2]) }

  m = atom.match(/^([\w.]+)\.starts_with\("((?:\\.|[^"\\])*)"\)$/)
  if (m) return { id, ...splitField(m[1]), operator: 'starts_with', value: unescape(m[2]) }

  m = atom.match(/^([\w.]+)\.matches\("((?:\\.|[^"\\])*)"\)$/)
  if (m) return { id, ...splitField(m[1]), operator: 'matches', value: unescape(m[2]) }

  m = atom.match(/^([\w.]+)\s*==\s*"((?:\\.|[^"\\])*)"$/)
  if (m) return { id, ...splitField(m[1]), operator: 'equals', value: unescape(m[2]) }

  m = atom.match(/^([\w.]+)\s*!=\s*"((?:\\.|[^"\\])*)"$/)
  if (m) return { id, ...splitField(m[1]), operator: 'not_equals', value: unescape(m[2]) }

  return null
}

function unescape(s: string): string {
  return s.replace(/\\"/g, '"').replace(/\\\\/g, '\\')
}

function mapField(raw: string): RuleField {
  if (raw.startsWith('header.')) return 'header'
  if (raw === 'user_agent') return 'ua'
  const f = raw as RuleField
  if (['path', 'method', 'host', 'ip', 'ua', 'country', 'asn', 'trusted_bot'].includes(f)) return f
  return 'path'
}

function splitField(raw: string): { field: RuleField; headerName?: string } {
  if (raw.startsWith('header.')) {
    return { field: 'header', headerName: raw.slice(7) }
  }
  return { field: mapField(raw) }
}

export function resolveBuilder(match: { expr?: string; _builder?: CustomRuleBuilderState }): CustomRuleBuilderState {
  if (match._builder?.conditions?.length) {
    return match._builder
  }
  const parsed = match.expr ? tryParseBuilder(match.expr) : null
  return parsed ?? defaultBuilderState()
}

export function syncMatchFromBuilder(
  builder: CustomRuleBuilderState,
  existing?: CustomRuleMatch,
): CustomRuleMatch {
  const expr = buildExpr(builder)
  return {
    ...existing,
    expr,
    _builder: builder,
  }
}

/** Ensure every rule has a fresh expr before persisting to API/engine. */
export function normalizeRulesForSave(rules: CustomRule[]) {
  return rules.map((rule) => {
    const builder = resolveBuilder(rule.match)
    const expr = buildExpr(builder)
    return {
      ...rule,
      match: {
        ...rule.match,
        expr,
        _builder: builder,
      },
    }
  })
}
