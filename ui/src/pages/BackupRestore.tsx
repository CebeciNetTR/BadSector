import { useState } from 'react'
import { api, ApiError } from '../api/client'

type SecretsMode = 'keep' | 'rotate' | 'skip'

export default function BackupRestore() {
  const [includeSecrets, setIncludeSecrets] = useState(true)
  const [secretsMode, setSecretsMode] = useState<SecretsMode>('keep')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [rotated, setRotated] = useState<Record<string, string> | null>(null)

  const download = async () => {
    setBusy(true)
    setErr(null)
    setMsg(null)
    try {
      await api.downloadBackup(includeSecrets)
      setMsg('Backup indirildi. Zip’i güvenli sakla — public git’e koyma.')
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const onRestore = async (file: File | null) => {
    if (!file) return
    if (!confirm('Restore mevcut siteleri/DB’yi SİLER ve backup ile değiştirir. Devam?')) return
    setBusy(true)
    setErr(null)
    setMsg(null)
    setRotated(null)
    try {
      const res = await api.restoreBackup(file, secretsMode)
      setMsg(res.message)
      if (res.rotated) setRotated(res.rotated)
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <header className="page-header">
        <h2>Backup / Restore</h2>
        <p style={{ color: 'var(--muted)', marginTop: '0.35rem' }}>
          Siteler, pipeline, SSL (PEM + ACME) ve isteğe bağlı secrets. Yeni kutuya taşımak veya DR için.
        </p>
      </header>

      <div className="card form-grid" style={{ marginBottom: '1.25rem' }}>
        <h3 style={{ gridColumn: '1 / -1' }}>Backup indir</h3>
        <label className="checkbox-row">
          <input
            type="checkbox"
            checked={includeSecrets}
            onChange={(e) => setIncludeSecrets(e.target.checked)}
          />
          Tüm secrets (JWT, challenge, ACME, trusted IPs…)
        </label>
        <p style={{ color: 'var(--muted)', fontSize: '0.85rem', gridColumn: '1 / -1', margin: 0 }}>
          <strong>Admin kullanıcı + şifre her zaman yedeklenir</strong> (checkbox kapalı olsa bile) —
          restore sonrası aynı hesapla giriş yaparsın. Checkbox: diğer secret’ları da zip’e ekler.
          Rotate yalnızca JWT / challenge / engine token yeniler; admin login korunur.
        </p>
        <button type="button" className="btn" disabled={busy} onClick={download}>
          {busy ? '…' : 'Backup.zip indir'}
        </button>
      </div>

      <div className="card form-grid">
        <h3 style={{ gridColumn: '1 / -1' }}>Restore</h3>
        <label>
          Secrets modu
          <select
            value={secretsMode}
            onChange={(e) => setSecretsMode(e.target.value as SecretsMode)}
          >
            <option value="keep">Keep — backup’taki secrets + aynı admin login</option>
            <option value="rotate">Rotate — JWT/challenge/engine token yenile (admin kullanıcı/şifre aynı kalır)</option>
            <option value="skip">Skip — sadece DB + certs (admin dahil secrets yazılmaz)</option>
          </select>
        </label>
        <label className="field" style={{ gridColumn: '1 / -1' }}>
          <span>Backup zip</span>
          <input
            type="file"
            accept=".zip,application/zip"
            disabled={busy}
            onChange={(e) => onRestore(e.target.files?.[0] ?? null)}
          />
        </label>
        <p style={{ color: 'var(--muted)', fontSize: '0.85rem', gridColumn: '1 / -1', margin: 0 }}>
          Restore sonrası: <code>data/restore/secrets.env</code> → host <code>.env</code> birleştir,
          sonra <code>docker compose up -d</code> ve <code>docker compose restart haproxy</code>.
          Rotate seçtiysen yeni admin şifresi yanıtta bir kez görünür.
        </p>
      </div>

      {msg && <p className="success-banner" style={{ marginTop: '1rem' }}>{msg}</p>}
      {err && <p className="error-banner" style={{ marginTop: '1rem' }}>{err}</p>}
      {rotated && (
        <div className="card" style={{ marginTop: '1rem' }}>
          <h3>Yeni secrets (bir kez — kaydet)</h3>
          <pre style={{ fontSize: '0.8rem', overflow: 'auto' }}>
            {Object.entries(rotated)
              .map(([k, v]) => `${k}=${v}`)
              .join('\n')}
          </pre>
        </div>
      )}
    </div>
  )
}
