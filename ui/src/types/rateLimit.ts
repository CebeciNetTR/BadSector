export type KeyBy = 'ip' | 'ip_path' | 'host' | 'global' | 'header' | 'cookie'
export type FailMode = 'open' | 'closed'

export interface RateLimitRule {
  id: string
  name: string
  enabled: boolean
  key_by: KeyBy
  header_name?: string
  cookie_name?: string
  limit: number
  burst: number
  window: string | number
  paths: string[]
  methods: string[]
}

export interface RateLimitRedisConfig {
  host: string
  port: number
  timeout: number
  enabled?: boolean
}

export interface RateLimitConfig {
  use_redis: boolean
  fail_mode: FailMode
  redis: RateLimitRedisConfig
  rules: RateLimitRule[]
}

export interface RateLimitResponse {
  enabled: boolean
  config: RateLimitConfig
}

export const defaultRateLimitConfig = (): RateLimitConfig => ({
  use_redis: true,
  fail_mode: 'open',
  redis: { host: 'redis', port: 6379, timeout: 100 },
  rules: [],
})

export const defaultRule = (): RateLimitRule => ({
  id: crypto.randomUUID(),
  name: '',
  enabled: true,
  key_by: 'ip',
  limit: 100,
  burst: 20,
  window: '1m',
  paths: ['/*'],
  methods: [],
})

export const KEY_BY_LABELS: Record<KeyBy, string> = {
  ip: 'IP adresi',
  ip_path: 'IP + path',
  host: 'Host',
  global: 'Site geneli',
  header: 'Header',
  cookie: 'Cookie',
}

export const WINDOW_PRESETS = [
  { value: '10s', label: '10 saniye' },
  { value: '1m', label: '1 dakika' },
  { value: '5m', label: '5 dakika' },
  { value: '1h', label: '1 saat' },
]

export const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']
