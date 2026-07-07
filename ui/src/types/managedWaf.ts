export type WafMode = 'block' | 'detect'

export interface ManagedWafConfig {
  ruleset: string
  paranoia_level: number
  mode: WafMode
  exclude_paths: string[]
  audit: boolean
  rules_dir: string
}

export interface ManagedWafResponse {
  enabled: boolean
  config: ManagedWafConfig
}

export const defaultManagedWafConfig = (): ManagedWafConfig => ({
  ruleset: 'coraza-crs',
  paranoia_level: 1,
  mode: 'block',
  exclude_paths: ['/badsector/health'],
  audit: true,
  rules_dir: '/etc/badsector/coraza/rules',
})

export const PARANOIA_LEVELS = [
  { value: 1, label: '1 — Temel (önerilen)' },
  { value: 2, label: '2 — Orta' },
  { value: 3, label: '3 — Yüksek' },
  { value: 4, label: '4 — Paranoid' },
]

export const WAF_MODES: { value: WafMode; label: string }[] = [
  { value: 'block', label: 'Engelle — eşleşmede 403' },
  { value: 'detect', label: 'Tespit — logla, geçir' },
]
