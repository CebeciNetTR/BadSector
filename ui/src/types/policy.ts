export type ConditionType =
  | 'host' | 'path' | 'method' | 'header' | 'cookie'
  | 'country' | 'asn' | 'ip' | 'cidr' | 'trusted_bot'
  | 'bot_score' | 'rate' | 'fingerprint' | 'request_size'
  | 'time' | 'variable'

export type ConditionOperator =
  | 'eq' | 'neq' | 'contains' | 'not_contains' | 'prefix'
  | 'suffix' | 'regex' | 'in' | 'not_in' | 'gt' | 'gte'
  | 'lt' | 'lte' | 'exists' | 'missing'

export type ActionType =
  | 'allow' | 'continue' | 'return_444' | 'block' | 'redirect'
  | 'js_challenge' | 'cookie_challenge' | 'captcha' | 'cache'
  | 'rate_limit' | 'log' | 'tag' | 'skip_module' | 'skip_remaining'

export interface PolicyCondition {
  type: ConditionType
  operator: ConditionOperator
  value?: string | number | boolean | string[]
  name?: string
}

export interface ConditionGroup {
  operator: 'and' | 'or'
  rules: PolicyCondition[]
}

export interface PolicyAction {
  type: ActionType
  status?: number
  body?: string
  url?: string
  message?: string
  level?: 'debug' | 'info' | 'warn' | 'error'
  value?: string
  retry_after?: number
}

export interface Policy {
  id: string
  site_id: string
  name: string
  priority: number
  enabled: boolean
  conditions: string
  actions: string
  created_at?: string
  updated_at?: string
}

export interface PolicyFormData {
  name: string
  priority: number
  enabled: boolean
  conditions: ConditionGroup
  actions: PolicyAction[]
}

export interface PolicyPayload {
  name: string
  priority: number
  enabled: boolean
  conditions: ConditionGroup
  actions: PolicyAction[]
}

export const CONDITION_TYPE_LABELS: Record<ConditionType, string> = {
  host: 'Host',
  path: 'Path',
  method: 'HTTP Method',
  header: 'Header',
  cookie: 'Cookie',
  country: 'Ülke',
  asn: 'ASN',
  ip: 'IP',
  cidr: 'CIDR',
  trusted_bot: 'Trusted Bot',
  bot_score: 'Bot Score',
  rate: 'Rate',
  fingerprint: 'Fingerprint',
  request_size: 'İstek Boyutu',
  time: 'Zaman',
  variable: 'Değişken',
}

export const ACTION_TYPE_LABELS: Record<ActionType, string> = {
  allow: 'İzin ver',
  continue: 'Devam et',
  return_444: '444 döndür',
  block: 'Engelle',
  redirect: 'Yönlendir',
  js_challenge: 'JS Challenge',
  cookie_challenge: 'Cookie Challenge',
  captcha: 'Captcha',
  cache: 'Cache',
  rate_limit: 'Rate Limit',
  log: 'Log',
  tag: 'Etiketle',
  skip_module: 'Modül atla',
  skip_remaining: 'Kalanı atla',
}

export const OPERATOR_LABELS: Record<ConditionOperator, string> = {
  eq: 'eşittir',
  neq: 'eşit değil',
  contains: 'içerir',
  not_contains: 'içermez',
  prefix: 'ile başlar',
  suffix: 'ile biter',
  regex: 'regex',
  in: 'listede',
  not_in: 'listede değil',
  gt: '>',
  gte: '>=',
  lt: '<',
  lte: '<=',
  exists: 'var',
  missing: 'yok',
}

export function parseConditions(raw: string): ConditionGroup {
  try {
    const parsed = JSON.parse(raw)
    if (parsed?.rules) return parsed as ConditionGroup
  } catch {
    // fallthrough
  }
  return { operator: 'and', rules: [] }
}

export function parseActions(raw: string): PolicyAction[] {
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function policyToForm(policy: Policy): PolicyFormData {
  return {
    name: policy.name,
    priority: policy.priority,
    enabled: policy.enabled,
    conditions: parseConditions(policy.conditions),
    actions: parseActions(policy.actions),
  }
}

export function defaultPolicyForm(): PolicyFormData {
  return {
    name: '',
    priority: 100,
    enabled: true,
    conditions: {
      operator: 'and',
      rules: [{ type: 'path', operator: 'prefix', value: '/' }],
    },
    actions: [{ type: 'continue' }],
  }
}

export function formToPolicyPayload(form: PolicyFormData): PolicyPayload {
  return {
    name: form.name.trim(),
    priority: form.priority || 100,
    enabled: form.enabled,
    conditions: form.conditions,
    actions: form.actions.length > 0 ? form.actions : [{ type: 'continue' }],
  }
}

export function summarizeConditions(group: ConditionGroup): string {
  if (!group.rules?.length) return 'Koşul yok'
  return group.rules
    .slice(0, 2)
    .map((r) => `${CONDITION_TYPE_LABELS[r.type] ?? r.type} ${OPERATOR_LABELS[r.operator] ?? r.operator}`)
    .join(` ${group.operator.toUpperCase()} `)
}

export function summarizeActions(actions: PolicyAction[]): string {
  if (!actions.length) return 'Aksiyon yok'
  return actions.map((a) => ACTION_TYPE_LABELS[a.type] ?? a.type).join(' → ')
}
