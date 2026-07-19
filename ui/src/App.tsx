import { useState, useEffect } from 'react'
import { Routes, Route, NavLink } from 'react-router-dom'
import { api, ApiError } from './api/client'
import { clearToken, onUnauthorized } from './lib/auth'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Sites from './pages/Sites'
import Policies from './pages/Policies'
import ManagedWaf from './pages/ManagedWaf'
import Pipeline from './pages/Pipeline'
import RateLimits from './pages/RateLimits'
import SecurityModules from './pages/SecurityModules'
import Trace from './pages/Trace'
import Certificates from './pages/Certificates'
import BackupRestore from './pages/BackupRestore'

const nav = [
  { to: '/', label: 'Dashboard' },
  { to: '/sites', label: 'Sites' },
  { to: '/policies', label: 'Policies' },
  { to: '/rate-limits', label: 'Rate Limits' },
  { to: '/security-modules', label: 'Edge Security' },
  { to: '/managed-waf', label: 'Managed WAF' },
  { to: '/pipeline', label: 'Pipeline' },
  { to: '/trace', label: 'Request Trace' },
  { to: '/certificates', label: 'Certificates' },
  { to: '/backup', label: 'Backup / Restore' },
  { to: '/modules', label: 'Modules' },
  { to: '/threat-intel', label: 'Threat Intelligence' },
  { to: '/analytics', label: 'Analytics' },
  { to: '/logs', label: 'Logs' },
  { to: '/settings', label: 'Settings' },
]

export default function App() {
  const [attackMode, setAttackMode] = useState<boolean>(false)
  const [attackLoaded, setAttackLoaded] = useState<boolean>(false)
  const [authState, setAuthState] = useState<'checking' | 'authed' | 'login'>('checking')

  // Doubles as the auth probe: a 401 here means we need to log in. Any other error
  // (backend unreachable, etc.) still lets the shell render so pages show their own errors.
  const verifyAuth = () => {
    api.getAttackMode()
      .then((res) => {
        setAttackMode(res.enabled)
        setAttackLoaded(true)
        setAuthState('authed')
      })
      .catch((err) => {
        if (err instanceof ApiError && err.status === 401) {
          setAuthState('login')
        } else {
          console.error('Failed to load attack mode status:', err)
          setAuthState('authed')
        }
      })
  }

  useEffect(() => {
    verifyAuth()
    const unsub = onUnauthorized(() => setAuthState('login'))
    return unsub
  }, [])

  const handleLogout = () => {
    clearToken()
    setAuthState('login')
  }

  const handleToggle = () => {
    const nextState = !attackMode
    setAttackMode(nextState)
    api.saveAttackMode(nextState)
      .catch((err) => {
        console.error('Failed to save attack mode status:', err)
        setAttackMode(!nextState) // revert on error
        alert('Failed to update attack mode: ' + err.message)
      })
  }

  if (authState === 'checking') {
    return (
      <div className="layout">
        <main className="main">
          <div className="card">
            <p className="empty-state">Yükleniyor…</p>
          </div>
        </main>
      </div>
    )
  }

  if (authState === 'login') {
    return <Login onSuccess={verifyAuth} />
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <h1>BadSector</h1>

        {attackLoaded && (
          <div className="attack-mode-panel">
            <div className="attack-mode-header">
              <span className="attack-mode-title">Mitigation</span>
              <div className="attack-mode-status">
                <span className={`status-dot ${attackMode ? 'active' : 'inactive'}`} />
                <span style={{ color: attackMode ? 'var(--fail)' : 'var(--pass)' }}>
                  {attackMode ? 'Under Attack' : 'Normal'}
                </span>
              </div>
            </div>
            <button 
              onClick={handleToggle}
              className={`attack-mode-btn ${attackMode ? 'active' : 'inactive'}`}
            >
              {attackMode ? 'Disable Attack Mode' : 'Enable Attack Mode'}
            </button>
          </div>
        )}

        <nav>
          {nav.map(({ to, label }) => (
            <NavLink key={to} to={to} end={to === '/'}>
              {label}
            </NavLink>
          ))}
        </nav>

        <button
          onClick={handleLogout}
          className="attack-mode-btn inactive"
          style={{ marginTop: '1rem', width: '100%' }}
        >
          Çıkış Yap
        </button>
      </aside>
      <main className="main">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/sites" element={<Sites />} />
          <Route path="/policies" element={<Policies />} />
          <Route path="/rate-limits" element={<RateLimits />} />
          <Route path="/security-modules" element={<SecurityModules />} />
          <Route path="/managed-waf" element={<ManagedWaf />} />
          <Route path="/pipeline" element={<Pipeline />} />
          <Route path="/trace" element={<Trace />} />
          <Route path="/certificates" element={<Certificates />} />
          <Route path="/backup" element={<BackupRestore />} />
          <Route path="*" element={<Placeholder title="Coming soon" />} />
        </Routes>
      </main>
    </div>
  )
}

function Placeholder({ title }: { title: string }) {
  return (
    <div className="card">
      <h2>{title}</h2>
      <p style={{ color: 'var(--muted)', marginTop: '0.5rem' }}>
        This section is under development.
      </p>
    </div>
  )
}
