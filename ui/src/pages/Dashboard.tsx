import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { DashboardMetrics } from '../types/metrics'

export default function Dashboard() {
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    const load = () => {
      api.getDashboardMetrics()
        .then(setMetrics)
        .catch((e) => setError(e instanceof Error ? e.message : 'Metrikler yüklenemedi'))
    }
    load()
    const timer = setInterval(load, 5000)
    return () => clearInterval(timer)
  }, [])

  return (
    <>
      <h2 style={{ marginBottom: '1.5rem' }}>Dashboard</h2>

      {error && <p className="form-error">{error}</p>}

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '1rem' }}>
        <StatCard label="Toplam İstek" value={fmt(metrics?.requests_total)} />
        <StatCard label="Engellenen" value={fmt(metrics?.blocked)} tone="fail" />
        <StatCard label="Challenge" value={fmt(metrics?.challenged)} tone="warn" />
        <StatCard label="Rate Limit" value={fmt(metrics?.rate_limited)} tone="warn" />
        <StatCard label="İzin Verilen" value={fmt(metrics?.allowed)} tone="pass" />
        <StatCard label="Banlı IP" value={fmt(metrics?.banned_ips)} tone="fail" />
        <StatCard label="İzlenen IP" value={fmt(metrics?.watched_ips)} tone="warn" />
        <StatCard label="Aktif Site" value={fmt(metrics?.active_sites)} />
      </div>

      <div className="card" style={{ marginTop: '1.5rem' }}>
        <h3 style={{ marginBottom: '0.75rem' }}>Edge Durumu</h3>
        <div className="edge-status">
          <StatusPill label="API" status={metrics?.edge.api ?? '—'} />
          <StatusPill label="Redis" status={metrics?.edge.redis ?? '—'} />
          <StatusPill label="Engine" status={metrics?.edge.engine ?? '—'} />
        </div>
        <p style={{ color: 'var(--muted)', marginTop: '0.75rem' }}>
          Metrikler engine tarafından Redis&apos;e yazılır. Trafik göndermek için{' '}
          <code>curl -H &quot;Host: localhost&quot; http://localhost:9080/</code>
        </p>
      </div>

      {metrics && Object.keys(metrics.decisions).length > 0 && (
        <div className="card" style={{ marginTop: '1rem' }}>
          <h3 style={{ marginBottom: '0.75rem' }}>Karar Dağılımı</h3>
          <div className="decision-grid">
            {Object.entries(metrics.decisions).map(([action, count]) => (
              <div key={action} className="decision-row">
                <span className="mono">{action}</span>
                <span>{count}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </>
  )
}

function fmt(n: number | undefined): string {
  if (n == null) return '—'
  return n.toLocaleString()
}

function StatCard({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: 'pass' | 'fail' | 'warn'
}) {
  return (
    <div className="card">
      <div style={{ color: 'var(--muted)', fontSize: '0.875rem' }}>{label}</div>
      <div
        style={{
          fontSize: '1.75rem',
          fontWeight: 600,
          marginTop: '0.25rem',
          color: tone === 'pass' ? 'var(--pass)' : tone === 'fail' ? 'var(--fail)' : tone === 'warn' ? 'var(--warn)' : undefined,
        }}
      >
        {value}
      </div>
    </div>
  )
}

function StatusPill({ label, status }: { label: string; status: string }) {
  const ok = status === 'ok'
  return (
    <div className={`status-pill ${ok ? 'ok' : 'down'}`}>
      <span>{label}</span>
      <span>{status}</span>
    </div>
  )
}
