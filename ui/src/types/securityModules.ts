export interface ModuleStageResponse<T = Record<string, unknown>> {
  enabled: boolean
  config: T
}
export interface GeoipConfig {
  database_path: string
  fail_open: boolean
  block_countries: string[]
  allow_countries: string[]
  allow_only: boolean
  use_header_fallback: boolean
}

export interface GeoipStatus {
  country_path: string
  asn_path: string
  country_ok: boolean
  asn_ok: boolean
  last_sync?: string
}

export interface AsnConfig {
  enabled?: boolean
  database_path: string
  block_asns: number[]
  allow_asns: number[]
  allow_only: boolean
  ip_map: Record<string, { number?: number; org?: string }>
  fail_open: boolean
}

export interface HeaderRule {
  header: string
  required?: boolean
  forbidden?: boolean
  pattern?: string
  paths?: string[]
}

export interface HeaderValidationConfig {
  enabled?: boolean
  required: string[]
  forbidden: string[]
  rules: HeaderRule[]
}

export interface BurstDetectionConfig {
  enabled?: boolean
  window: number
  threshold: number
  key_by: 'ip' | 'ip_path' | 'global'
  paths: string[]
  action: 'rate_limit' | 'block'
  fail_open: boolean
}

export interface JsChallengeConfig {
  enabled?: boolean
  paths: string[]
  exclude_paths: string[]
  cookie_name: string
  cookie_ttl: number
}

export interface CookieChallengeConfig {
  enabled?: boolean
  paths: string[]
  exclude_paths: string[]
  cookie_name: string
  cookie_ttl: number
}

export type CustomRuleActionType =
  | 'block'
  | 'allow'
  | 'rate_limit'
  | 'redirect'
  | 'continue'
  | 'log'
  | 'return_444'

export interface CustomRuleAction {
  type: CustomRuleActionType
  status?: number
  body?: string
  url?: string
  retry_after?: number
  message?: string
}

export interface CustomRuleMatch {
  expr?: string
  /** UI-only: visual builder state (engine ignores). */
  _builder?: import('./customRuleBuilder').CustomRuleBuilderState
  operator?: 'and' | 'or'
  conditions?: Array<Record<string, unknown>>
}

export interface CustomRule {
  id: string
  name: string
  enabled?: boolean
  priority?: number
  match: CustomRuleMatch
  action: CustomRuleAction
}

export interface CustomRulesConfig {
  enabled?: boolean
  fail_open: boolean
  rules: CustomRule[]
}

export interface CertificateRecord {
  id: string
  site_id: string
  domain: string
  email: string
  issuer: string
  status: 'pending' | 'active' | 'expired' | 'error' | 'renewing'
  auto_renew: boolean
  expires_at?: string
  last_renewed_at?: string
  last_error?: string
  created_at?: string
  updated_at?: string
}

export function defaultGeoipConfig(): GeoipConfig {
  return {
    database_path: '/etc/badsector/geoip/GeoLite2-Country.mmdb',
    fail_open: true,
    block_countries: [],
    allow_countries: [],
    allow_only: false,
    use_header_fallback: true,
  }
}

export function defaultAsnConfig(): AsnConfig {
  return {
    database_path: '/etc/badsector/geoip/GeoLite2-ASN.mmdb',
    block_asns: [],
    allow_asns: [],
    allow_only: false,
    ip_map: {},
    fail_open: true,
  }
}

export function defaultHeaderValidationConfig(): HeaderValidationConfig {
  return { required: [], forbidden: [], rules: [] }
}

export function defaultBurstDetectionConfig(): BurstDetectionConfig {
  return {
    window: 10,
    threshold: 50,
    key_by: 'ip',
    paths: ['/*'],
    action: 'rate_limit',
    fail_open: true,
  }
}

export function defaultJsChallengeConfig(): JsChallengeConfig {
  return {
    paths: ['/*'],
    exclude_paths: ['/badsector/*'],
    cookie_name: 'bs_js_ok',
    cookie_ttl: 3600,
  }
}

export function defaultCookieChallengeConfig(): CookieChallengeConfig {
  return {
    paths: ['/*'],
    exclude_paths: ['/badsector/*'],
    cookie_name: 'bs_verified',
    cookie_ttl: 86400,
  }
}

export function defaultCustomRulesConfig(): CustomRulesConfig {
  return { enabled: true, fail_open: true, rules: [] }
}

export function newCustomRule(partial?: Partial<CustomRule>): CustomRule {
  return {
    id: `rule-${Date.now()}`,
    name: 'Yeni kural',
    enabled: true,
    priority: 100,
    match: { expr: 'path.starts_with("/")' },
    action: { type: 'block', status: 403 },
    ...partial,
  }
}
