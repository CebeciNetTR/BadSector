export interface DashboardMetrics {
  requests_total: number
  blocked: number
  challenged: number
  rate_limited: number
  allowed: number
  banned_ips: number
  watched_ips: number
  active_sites: number
  decisions: Record<string, number>
  edge: {
    api: string
    engine: string
    redis: string
  }
}
