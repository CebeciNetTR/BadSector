export type CanonicalHostMode = 'none' | 'apex' | 'www'

export interface SiteSettings {
  debug_trace?: boolean
  live_trace?: boolean
  /** Edge redirect: force apex or www (301 to HTTPS). Both hostnames must be listed in Hosts. */
  canonical_host?: CanonicalHostMode
}
export interface Site {
  id: string
  name: string
  hosts: string
  settings: string
  enabled: boolean
  created_at?: string
  updated_at?: string
  pipeline?: PipelineStage[]
  policies?: unknown[]
}

export interface PipelineStage {
  id: string
  site_id: string
  module: string
  order: number
  enabled: boolean
  config?: string
}

export interface SiteDetail extends Site {
  pipeline: PipelineStage[]
}

export interface SiteFormData {
  name: string
  hosts: string[]
  enabled: boolean
  backend_url: string
  settings: SiteSettings
}

export interface SitePayload {
  name: string
  hosts: string[]
  enabled: boolean
  backend_url: string
  settings: SiteSettings
}

export const DEFAULT_BACKEND_URL = 'http://127.0.0.1:8081'

export const MODULE_LABELS: Record<string, string> = {
  access_lists: 'Access Lists',
  trusted_bots: 'Trusted Bots',
  ip_reputation: 'IP Reputation',
  geoip: 'GeoIP',
  asn: 'ASN',
  header_validation: 'Header Validation',
  custom_rules: 'Custom Rules',
  policies: 'Politikalar',
  rate_limiter: 'Rate Limit',
  burst_detection: 'Burst Detection',
  js_challenge: 'JS Challenge',
  cookie_challenge: 'Cookie Challenge',
  threat_intel: 'Threat Intelligence',
  cache: 'Cache',
  managed_waf: 'Managed WAF',
  reverse_proxy: 'Reverse Proxy',
}

export function parseHosts(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function parseSettings(raw: string): SiteSettings {
  try {
    const parsed = JSON.parse(raw)
    return typeof parsed === 'object' && parsed !== null ? parsed : {}
  } catch {
    return {}
  }
}

export function parseStageConfig(raw?: string): Record<string, unknown> {
  if (!raw) return {}
  try {
    const parsed = JSON.parse(raw)
    return typeof parsed === 'object' && parsed !== null ? parsed : {}
  } catch {
    return {}
  }
}

export function getBackendFromPipeline(stages: PipelineStage[] = []): string {
  const proxy = stages.find((s) => s.module === 'reverse_proxy')
  if (!proxy) return DEFAULT_BACKEND_URL
  const cfg = parseStageConfig(proxy.config)
  if (typeof cfg.backend_url === 'string' && cfg.backend_url) {
    return cfg.backend_url
  }
  if (typeof cfg.upstream === 'string' && cfg.upstream) {
    return `http://${cfg.upstream}`
  }
  return DEFAULT_BACKEND_URL
}

export function hostsToInput(hosts: string[]): string {
  return hosts.join('\n')
}

export function inputToHosts(input: string): string[] {
  return input
    .split(/[\n,]+/)
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean)
}

export function siteToForm(site: Site, pipeline: PipelineStage[] = []): SiteFormData {
  return {
    name: site.name,
    hosts: parseHosts(site.hosts),
    enabled: site.enabled,
    backend_url: getBackendFromPipeline(pipeline),
    settings: parseSettings(site.settings),
  }
}

export function defaultSiteForm(): SiteFormData {
  return {
    name: '',
    hosts: [],
    enabled: true,
    backend_url: DEFAULT_BACKEND_URL,
    settings: { debug_trace: false },
  }
}

export function formToPayload(form: SiteFormData): SitePayload {
  return {
    name: form.name.trim(),
    hosts: form.hosts,
    enabled: form.enabled,
    backend_url: form.backend_url.trim(),
    settings: form.settings,
  }
}
