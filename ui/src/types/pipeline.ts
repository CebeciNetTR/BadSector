import { DEFAULT_BACKEND_URL, MODULE_LABELS, type PipelineStage } from './site'

export const LOCKED_LAST_MODULE = 'reverse_proxy'

export interface EditablePipelineStage {
  key: string
  module: string
  enabled: boolean
  config: string
}

export interface PipelineStagePayload {
  module: string
  enabled: boolean
  config: string
}

export const IMPLEMENTED_MODULES = [
  'access_lists',
  'trusted_bots',
  'ip_reputation',
  'geoip',
  'asn',
  'header_validation',
  'custom_rules',
  'policies',
  'rate_limiter',
  'burst_detection',
  'js_challenge',
  'cookie_challenge',
  'threat_intel',
  'cache',
  'managed_waf',
  'reverse_proxy',
] as const

export const ALL_MODULES = Object.keys(MODULE_LABELS)

export const DEFAULT_MODULE_CONFIG: Record<string, string> = {
  access_lists: JSON.stringify({ deny: [], allow: [] }),
  policies: JSON.stringify({ rules: [] }),
  rate_limiter: JSON.stringify({
    use_redis: true,
    fail_mode: 'open',
    redis: { host: 'redis', port: 6379, timeout: 100 },
    rules: [],
  }),
  reverse_proxy: JSON.stringify({
    upstream: 'backend',
    backend_url: DEFAULT_BACKEND_URL,
  }),
  geoip: JSON.stringify({
    database_path: '/etc/badsector/geoip/GeoLite2-Country.mmdb',
    fail_open: true,
    block_countries: [],
    allow_countries: [],
    allow_only: false,
    use_header_fallback: true,
  }),
  trusted_bots: JSON.stringify({
    enabled: true,
    mark_trusted: true,
    verify_ip: true,
    custom_bots: [],
  }),
  ip_reputation: JSON.stringify({
    enabled: true,
    block_ips: [],
    block_cidrs: [],
    use_redis_feed: false,
    redis_key: 'badsector:reputation:bad',
    fail_open: true,
  }),
  asn: JSON.stringify({
    enabled: true,
    database_path: '/etc/badsector/geoip/GeoLite2-ASN.mmdb',
    block_asns: [],
    allow_asns: [],
    allow_only: false,
    ip_map: {},
    fail_open: true,
  }),
  header_validation: JSON.stringify({ enabled: true, required: [], forbidden: [], rules: [] }),
  custom_rules: JSON.stringify({ enabled: true, fail_open: true, rules: [] }),
  burst_detection: JSON.stringify({ enabled: true, window: 10, threshold: 50, key_by: 'ip', paths: ['/*'], action: 'rate_limit', fail_open: true }),
  js_challenge: JSON.stringify({ enabled: false, paths: ['/*'], exclude_paths: ['/badsector/*'], cookie_name: 'bs_js_ok', cookie_ttl: 3600 }),
  cookie_challenge: JSON.stringify({ enabled: false, paths: ['/*'], exclude_paths: ['/badsector/*'], cookie_name: 'bs_verified', cookie_ttl: 86400 }),
  threat_intel: JSON.stringify({ enabled: true, redis_key: 'badsector:threat_intel:bad', fail_open: true }),
  cache: JSON.stringify({ enabled: false, ttl: 60 }),
  managed_waf: JSON.stringify({
    ruleset: 'coraza-crs',
    paranoia_level: 1,
    mode: 'block',
    exclude_paths: ['/badsector/health'],
    audit: true,
    rules_dir: '/etc/badsector/coraza/rules',
  }),
}

let keyCounter = 0

export function newStageKey(): string {
  keyCounter += 1
  return `stage-${Date.now()}-${keyCounter}`
}

export function stagesFromApi(stages: PipelineStage[]): EditablePipelineStage[] {
  return [...stages]
    .sort((a, b) => a.order - b.order)
    .map((s) => ({
      key: s.id || newStageKey(),
      module: s.module,
      enabled: s.enabled,
      config: s.config ?? DEFAULT_MODULE_CONFIG[s.module] ?? '{}',
    }))
}

export function stagesToPayload(stages: EditablePipelineStage[]): PipelineStagePayload[] {
  // Config'i bos gonder: Pipeline sayfasi sadece sira/enabled duzenler.
  // Sunucu mevcut DB config'ini korur (DEFAULT placeholder GeoIP vb. ezmesin).
  return stages.map((s) => ({
    module: s.module,
    enabled: s.enabled,
    config: '',
  }))
}

export function splitPipeline(stages: EditablePipelineStage[]) {
  const proxy = stages.find((s) => s.module === LOCKED_LAST_MODULE)
  const draggable = stages.filter((s) => s.module !== LOCKED_LAST_MODULE)
  return { draggable, proxy }
}

export function mergePipeline(
  draggable: EditablePipelineStage[],
  proxy: EditablePipelineStage | undefined,
): EditablePipelineStage[] {
  if (proxy) return [...draggable, proxy]
  return [...draggable]
}

export function moveStage(
  stages: EditablePipelineStage[],
  fromIndex: number,
  toIndex: number,
): EditablePipelineStage[] {
  const { draggable, proxy } = splitPipeline(stages)
  if (fromIndex < 0 || fromIndex >= draggable.length) return stages
  if (toIndex < 0 || toIndex >= draggable.length) return stages

  const next = [...draggable]
  const [item] = next.splice(fromIndex, 1)
  next.splice(toIndex, 0, item)
  return mergePipeline(next, proxy)
}

export function toggleStage(
  stages: EditablePipelineStage[],
  key: string,
  enabled: boolean,
): EditablePipelineStage[] {
  return stages.map((s) => (s.key === key ? { ...s, enabled } : s))
}

export function removeStage(stages: EditablePipelineStage[], key: string): EditablePipelineStage[] {
  const stage = stages.find((s) => s.key === key)
  if (!stage || stage.module === LOCKED_LAST_MODULE) return stages
  return stages.filter((s) => s.key !== key)
}

export function addModule(stages: EditablePipelineStage[], module: string): EditablePipelineStage[] {
  if (stages.some((s) => s.module === module)) return stages

  const newStage: EditablePipelineStage = {
    key: newStageKey(),
    module,
    enabled: true,
    config: DEFAULT_MODULE_CONFIG[module] ?? '{}',
  }

  const { draggable, proxy } = splitPipeline(stages)
  return mergePipeline([...draggable, newStage], proxy)
}

export function availableModules(stages: EditablePipelineStage[]): string[] {
  const used = new Set(stages.map((s) => s.module))
  return IMPLEMENTED_MODULES.filter((m) => !used.has(m))
}

export function moduleLabel(module: string): string {
  return MODULE_LABELS[module] ?? module
}

export function ensureReverseProxy(stages: EditablePipelineStage[]): EditablePipelineStage[] {
  if (stages.some((s) => s.module === LOCKED_LAST_MODULE)) {
    return stages
  }
  return mergePipeline(stages, {
    key: newStageKey(),
    module: LOCKED_LAST_MODULE,
    enabled: true,
    config: DEFAULT_MODULE_CONFIG[LOCKED_LAST_MODULE],
  })
}
