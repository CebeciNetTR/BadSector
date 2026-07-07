export interface TraceStep {
  module: string
  decision: string
  ms?: number
  detail?: string
  bot?: string
  verified?: boolean
}

export interface RequestTrace {
  id: string
  ts: number
  method: string
  path: string
  host?: string
  remote_addr: string
  user_agent?: string
  decision: string
  status?: number
  duration_ms: number
  steps: TraceStep[]
}
