import { useCallback, useEffect, useState } from 'react'
import { api, ApiError } from '../api/client'
import { clearToken, getToken, setToken } from '../lib/auth'
import type { RequestTrace } from '../types/trace'
import type { Site } from '../types/site'

function decisionClass(decision: string): string {
  if (decision === 'CONTINUE' || decision === 'ALLOW') return 'pass'
  if (decision === 'BLOCK' || decision === 'RATE_LIMIT' || decision === 'RETURN_444') return 'match'
  return 'fail'
}

function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleTimeString()
}

export default function Trace() {
  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState('')
  const [traces, setTraces] = useState<RequestTrace[]>([])
  const [selected, setSelected] = useState<RequestTrace | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [authRequired, setAuthRequired] = useState<boolean | null>(null)
  const [token, setTokenState] = useState(getToken)
  const [loginUser, setLoginUser] = useState('admin')
  const [loginPass, setLoginPass] = useState('badsector')
  const [loginError, setLoginError] = useState('')

  useEffect(() => {
    api.listSites()
      .then((list) => {
        setAuthRequired(false)
        setSites(list)
        if (list.length > 0) setSiteId(list[0].id)
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) {
          setAuthRequired(true)
        } else {
          setError(e instanceof Error ? e.message : 'Site listesi yüklenemedi')
        }
      })
      .finally(() => setLoading(false))
  }, [])

  const loadTraces = useCallback(async () => {
    if (!siteId) return
    try {
      const data = await api.listTraces(siteId, 50)
      setTraces(data)
      setError('')
      if (data.length > 0 && (!selected || !data.some((t) => t.id === selected.id))) {
        setSelected(data[0])
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Trace yüklenemedi')
    }
  }, [siteId, selected])

  useEffect(() => {
    if (!siteId) return
    loadTraces()
    const timer = setInterval(loadTraces, 2000)
    return () => clearInterval(timer)
  }, [siteId, loadTraces])

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setLoginError('')
    try {
      const resp = await api.login(loginUser, loginPass)
      setToken(resp.token)
      setTokenState(resp.token)
      setLoading(true)
      const list = await api.listSites()
      setSites(list)
      if (list.length > 0) setSiteId(list[0].id)
      setError('')
    } catch (err) {
      setLoginError(err instanceof Error ? err.message : 'Giriş başarısız')
    } finally {
      setLoading(false)
    }
  }

  function handleLogout() {
    clearToken()
    setTokenState(null)
    setTraces([])
    setSelected(null)
  }

  if (authRequired && !token) {
    return (
      <>
        <h2 style={{ marginBottom: '1.5rem' }}>Canlı İstek İzleme</h2>
        <div className="card" style={{ maxWidth: 420 }}>
          <h3>API Girişi</h3>
          <p className="empty-state" style={{ marginBottom: '1rem' }}>
            Trace verileri korumalı API üzerinden gelir. Dev ortamında auth kapalıysa token gerekmez.
          </p>
          <form className="form-grid" onSubmit={handleLogin}>
            <label>
              Kullanıcı
              <input value={loginUser} onChange={(e) => setLoginUser(e.target.value)} />
            </label>
            <label>
              Şifre
              <input
                type="password"
                value={loginPass}
                onChange={(e) => setLoginPass(e.target.value)}
              />
            </label>
            {loginError && <p className="form-error">{loginError}</p>}
            <button type="submit" className="btn-primary">Giriş Yap</button>
          </form>
        </div>
      </>
    )
  }

  return (
    <>
      <div className="page-header">
        <h2>Canlı İstek İzleme</h2>
        {authRequired && token && (
          <button type="button" className="btn-secondary" onClick={handleLogout}>
            Çıkış
          </button>
        )}
      </div>

      <div className="card">
        <div className="form-row">
          <label>
            Site
            <select value={siteId} onChange={(e) => setSiteId(e.target.value)}>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>
          </label>
          <button type="button" className="btn-secondary" onClick={loadTraces}>
            Yenile
          </button>
        </div>
        <p style={{ color: 'var(--muted)', marginTop: '0.75rem' }}>
          Her istek pipeline adımlarıyla birlikte Redis&apos;te tutulur. Site ayarlarında{' '}
          <code>live_trace: true</code> olmalıdır. 2 saniyede bir güncellenir.
        </p>
        {error && <p className="form-error">{error}</p>}
      </div>

      <div className="trace-layout">
        <div className="card trace-list">
          <h3>Son İstekler</h3>
          {loading && traces.length === 0 ? (
            <p className="empty-state">Yükleniyor…</p>
          ) : traces.length === 0 ? (
            <p className="empty-state">Henüz trace yok. Engine&apos;e istek gönderin.</p>
          ) : (
            <ul className="trace-items">
              {traces.map((t) => (
                <li key={`${t.id}-${t.ts}`}>
                  <button
                    type="button"
                    className={`trace-item ${selected?.id === t.id && selected?.ts === t.ts ? 'active' : ''}`}
                    onClick={() => setSelected(t)}
                  >
                    <span className={`badge ${decisionClass(t.decision)}`}>{t.decision}</span>
                    <span className="mono">{t.method} {t.path}</span>
                    <span className="muted-inline">{t.remote_addr}</span>
                    <span className="muted-inline">{formatTime(t.ts)} · {t.duration_ms}ms</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="card trace-detail">
          <h3>Explainability</h3>
          {!selected ? (
            <p className="empty-state">Detay için bir istek seçin.</p>
          ) : (
            <>
              <div className="trace-meta">
                <div><strong>ID</strong> <span className="mono">{selected.id}</span></div>
                <div><strong>Karar</strong> {selected.decision}{selected.status ? ` (${selected.status})` : ''}</div>
                <div><strong>IP</strong> {selected.remote_addr}</div>
                <div><strong>Süre</strong> {selected.duration_ms} ms</div>
              </div>
              <div className="trace-flow" style={{ marginTop: '1rem' }}>
                {selected.steps.map((step, i) => (
                  <div
                    key={`${step.module}-${i}`}
                    className={`trace-step ${decisionClass(step.decision)}`}
                  >
                    <span>{step.module}</span>
                    <span className={`badge ${decisionClass(step.decision)}`}>{step.decision}</span>
                    {step.detail && <span style={{ color: 'var(--muted)' }}>{step.detail}</span>}
                    {step.ms != null && (
                      <span className="muted-inline">{Math.round(step.ms)}ms</span>
                    )}
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </>
  )
}
