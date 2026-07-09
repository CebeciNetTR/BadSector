/** Visual custom rule builder — maps to engine expr.lua syntax. */

export type RuleField =
  | 'path'
  | 'method'
  | 'host'
  | 'ip'
  | 'ua'
  | 'country'
  | 'asn'
  | 'trusted_bot'
  | 'header'

export type RuleOperator =
  | 'equals'
  | 'not_equals'
  | 'contains'
  | 'not_contains'
  | 'starts_with'
  | 'not_starts_with'
  | 'matches'
  | 'in_list'
  | 'not_in_list'
  | 'is_true'
  | 'is_false'

export interface VisualCondition {
  id: string
  field: RuleField
  headerName?: string
  operator: RuleOperator
  value: string
}

export interface CustomRuleBuilderState {
  logic: 'and' | 'or'
  conditions: VisualCondition[]
}

export const RULE_FIELD_LABELS: Record<RuleField, string> = {
  path: 'URL yolu (path)',
  method: 'HTTP metodu',
  host: 'Host',
  ip: 'İstemci IP',
  ua: 'User-Agent',
  country: 'Ülke kodu',
  asn: 'ASN numarası',
  trusted_bot: 'Doğrulanmış bot',
  header: 'HTTP header',
}

export const RULE_FIELD_HINTS: Record<RuleField, string> = {
  path: 'Örn: /wp-admin, /api/*',
  method: 'GET, POST, …',
  host: 'www.example.com',
  ip: '1.2.3.4',
  ua: 'curl, bot, …',
  country: 'TR, US, DE (ISO)',
  asn: '9121',
  trusted_bot: 'trusted_bots modülünden; Googlebot vb.',
  header: 'Özel header adı girin',
}

export const OPERATORS_BY_FIELD: Record<RuleField, RuleOperator[]> = {
  path: ['contains', 'not_contains', 'starts_with', 'not_starts_with', 'equals', 'not_equals', 'matches'],
  method: ['equals', 'not_equals', 'in_list', 'not_in_list'],
  host: ['equals', 'not_equals', 'contains', 'starts_with'],
  ip: ['equals', 'not_equals', 'in_list'],
  ua: ['contains', 'not_contains', 'matches'],
  country: ['equals', 'not_equals', 'in_list', 'not_in_list'],
  asn: ['equals', 'not_equals', 'in_list', 'not_in_list'],
  trusted_bot: ['is_true', 'is_false'],
  header: ['contains', 'not_contains', 'equals', 'not_equals', 'matches'],
}

export const OPERATOR_LABELS: Record<RuleOperator, string> = {
  equals: 'eşittir',
  not_equals: 'eşit değildir',
  contains: 'içerir',
  not_contains: 'içermez',
  starts_with: 'ile başlar',
  not_starts_with: 'ile başlamaz',
  matches: 'regex eşleşir',
  in_list: 'listedeki değerlerden biri',
  not_in_list: 'listedekilerden biri değil',
  is_true: 'doğru (evet)',
  is_false: 'doğru değil (hayır)',
}

export interface RuleTemplate {
  id: string
  name: string
  description: string
  rule: {
    name: string
    priority?: number
    match: { expr: string; _builder: CustomRuleBuilderState }
    action: { type: 'block'; status: number } | { type: 'return_444' }
  }
}

export const RULE_TEMPLATES: RuleTemplate[] = [
  {
    id: 'homepage-only-lockdown',
    name: 'Acil mod — sadece ana sayfa (444)',
    description:
      'Yalnızca / geçer (domain.com ve domain.com/). Diğer tüm yollar 444 ile kapatılır — ağır saldırı / lockdown modu.',
    rule: {
      name: 'Homepage only lockdown',
      priority: 10,
      match: {
        expr: 'path != "/"',
        _builder: {
          logic: 'and',
          conditions: [{ id: 'c1', field: 'path', operator: 'not_equals', value: '/' }],
        },
      },
      action: { type: 'return_444' },
    },
  },
  {
    id: 'wp-probe',
    name: 'WordPress tarama — bot hariç engelle',
    description: 'URL\'de wp- geçen istekleri engeller; doğrulanmış botlar geçer.',
    rule: {
      name: 'WordPress probe block',
      match: {
        expr: 'path contains "wp-" and trusted_bot != true',
        _builder: {
          logic: 'and',
          conditions: [
            { id: 'c1', field: 'path', operator: 'contains', value: 'wp-' },
            { id: 'c2', field: 'trusted_bot', operator: 'is_false', value: '' },
          ],
        },
      },
      action: { type: 'block', status: 403 },
    },
  },
  {
    id: 'block-curl',
    name: 'curl / wget engelle',
    description: 'User-Agent içinde curl veya wget geçen istekleri engeller.',
    rule: {
      name: 'Block curl/wget',
      match: {
        expr: 'ua contains "curl" or ua contains "wget"',
        _builder: {
          logic: 'or',
          conditions: [
            { id: 'c1', field: 'ua', operator: 'contains', value: 'curl' },
            { id: 'c2', field: 'ua', operator: 'contains', value: 'wget' },
          ],
        },
      },
      action: { type: 'block', status: 403 },
    },
  },
  {
    id: 'admin-path',
    name: '/admin yolu — sadece TR',
    description: '/admin ile başlayan yollar; ülke TR değilse engelle.',
    rule: {
      name: 'Admin geo TR only',
      match: {
        expr: 'path.starts_with("/admin") and country not in ["TR"]',
        _builder: {
          logic: 'and',
          conditions: [
            { id: 'c1', field: 'path', operator: 'starts_with', value: '/admin' },
            { id: 'c2', field: 'country', operator: 'not_in_list', value: 'TR' },
          ],
        },
      },
      action: { type: 'block', status: 403 },
    },
  },
]

export function newCondition(partial?: Partial<VisualCondition>): VisualCondition {
  return {
    id: `c-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    field: 'path',
    operator: 'contains',
    value: '',
    ...partial,
  }
}

export function defaultBuilderState(): CustomRuleBuilderState {
  return {
    logic: 'and',
    conditions: [newCondition({ operator: 'contains', value: '' })],
  }
}
