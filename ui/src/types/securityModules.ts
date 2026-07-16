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
  // Imzali Proof-of-Work (stateless HMAC)
  difficulty: number
  difficulty_attack: number
  pass_ttl: number
  pass_cookie?: string
  pow_cookie?: string
  ban_threshold?: number
  ban_ttl?: number
  /** Özel challenge HTML/CSS. Boşsa engine varsayılan şablonu kullanır.
   *  PoW çözücü <script> her zaman engine tarafından enjekte edilir. */
  template?: string
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
    difficulty: 4,
    difficulty_attack: 5,
    pass_ttl: 3600,
    pass_cookie: 'bs_pass',
    pow_cookie: 'bs_pow',
    ban_threshold: 3,
    ban_ttl: 86400,
    template: '',
  }
}

/** Engine'deki varsayılan challenge şablonu (challenge.lua default_template ile
 *  aynı). Editöre "Varsayılanı yükle" ile bir başlangıç noktası verir.
 *  PoW çözücü <script> engine tarafından otomatik eklenir — buraya yazma. */
export const DEFAULT_CHALLENGE_TEMPLATE = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Check | BadSector</title>
    <style>
        body {
            background-color: #0f172a;
            color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            overflow: hidden;
        }
        .container {
            text-align: center;
            max-width: 450px;
            padding: 40px;
            background: rgba(30, 41, 59, 0.7);
            border-radius: 16px;
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.4);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        h1 { font-size: 24px; margin-bottom: 12px; font-weight: 600; }
        p { color: #94a3b8; font-size: 15px; line-height: 1.5; margin-bottom: 24px; }
        .spinner {
            width: 48px; height: 48px;
            border: 4px solid rgba(255, 255, 255, 0.1);
            border-left-color: #3b82f6;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px auto;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        noscript { color: #f87171; }
    </style>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>Checking your browser</h1>
        <p>Verifying your connection before continuing. This is automatic and helps block malicious traffic.</p>
        <noscript>JavaScript is required to continue.</noscript>
    </div>
</body>
</html>`

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
