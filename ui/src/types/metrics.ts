export interface DashboardMetrics {
  requests_total: number
  blocked: number
  challenged: number
  rate_limited: number
  allowed: number
  active_sites: number
  decisions: Record<string, number>
  edge: {
    api: string
    engine: string
    redis: string
  }
}
