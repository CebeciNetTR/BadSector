import { useState, useEffect } from 'react'
import { Routes, Route, NavLink } from 'react-router-dom'
import { api } from './api/client'
import Dashboard from './pages/Dashboard'
import Sites from './pages/Sites'
import Policies from './pages/Policies'
import ManagedWaf from './pages/ManagedWaf'
import Pipeline from './pages/Pipeline'
import RateLimits from './pages/RateLimits'
import SecurityModules from './pages/SecurityModules'
import Trace from './pages/Trace'
import Certificates from './pages/Certificates'

const nav = [
  { to: '/', label: 'Dashboard' },
  { to: '/sites', label: 'Sites' },
  { to: '/policies', label: 'Policies' },
  { to: '/rate-limits', label: 'Rate Limits' },
  { to: '/security-modules', label: 'Edge Security' },
  { to: '/managed-waf', label: 'Managed WAF' },
  { to: '/pipeline', label: 'Pipeline' },
  { to: '/trace', label: 'Request Trace' },
  { to: '/modules', label: 'Modules' },
  { to: '/certificates', label: 'Certificates' },
  { to: '/threat-intel', label: 'Threat Intelligence' },
  { to: '/analytics', label: 'Analytics' },
  { to: '/logs', label: 'Logs' },
  { to: '/settings', label: 'Settings' },
]

export default function App() {
  const [attackMode, setAttackMode] = useState<boolean>(false)
  const [loading, setLoading] = useState<boolean>(true)

  useEffect(() => {
    api.getAttackMode()
      .then((res) => {
        setAttackMode(res.enabled)
        setLoading(false)
      })
      .catch((err) => {
        console.error('Failed to load attack mode status:', err)
        setLoading(false)
      })
  }, [])

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

  return (
    <div className="layout">
      <aside className="sidebar">
        <h1>BadSector</h1>

        {!loading && (
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
