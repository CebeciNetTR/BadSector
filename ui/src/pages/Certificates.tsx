import { useCallback, useEffect, useState } from 'react'
import { api, ApiError } from '../api/client'
import { parseHosts, type Site } from '../types/site'
import type { CertificateRecord } from '../types/securityModules'

const statusClass: Record<string, string> = {
  active: 'ok',
  pending: 'down',
  renewing: 'down',
  error: 'down',
  expired: 'down',
}

export default function Certificates() {
  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState('')
  const [certs, setCerts] = useState<CertificateRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const [domain, setDomain] = useState('')
  const [email, setEmail] = useState('')
  const [autoRenew, setAutoRenew] = useState(true)

  const loadSites = useCallback(async () => {
    const list = await api.listSites()
    setSites(list)
    if (list.length > 0) {
      setSiteId((c) => c || list[0].id)
    }
  }, [])

  const loadCerts = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const items = id ? await api.listSiteCertificates(id) : await api.listCertificates()
      setCerts(items)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Sertifikalar yüklenemedi')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadSites().catch((e) => setError(e.message))
  }, [loadSites])

  useEffect(() => {
    if (siteId) loadCerts(siteId)
  }, [siteId, loadCerts])

  async function requestCert(issue: boolean) {
    if (!siteId || !domain.trim()) return
    setBusy('create')
    setError(null)
    setSuccess(null)
    try {
      const created = await api.createCertificate(siteId, {
        domain: domain.trim(),
        email: email.trim(),
        auto_renew: autoRenew,
        issue,
      })
      setSuccess(issue ? `Sertifika istendi: ${created.domain}` : `Kayıt oluşturuldu: ${created.domain}`)
      setDomain('')
      await loadCerts(siteId)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'İşlem başarısız')
    } finally {
      setBusy(null)
    }
  }

  async function issue(certId: string) {
    setBusy(certId)
    setError(null)
    try {
      await api.issueCertificate(certId)
      setSuccess('Sertifika alındı')
      if (siteId) await loadCerts(siteId)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Sertifika alınamadı')
    } finally {
      setBusy(null)
    }
  }

  async function renew(certId: string) {
    setBusy(certId)
    setError(null)
    try {
      await api.renewCertificate(certId)
      setSuccess('Sertifika yenilendi')
      if (siteId) await loadCerts(siteId)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Yenileme başarısız')
    } finally {
      setBusy(null)
    }
  }

  async function remove(certId: string) {
    if (!confirm('Sertifika silinsin mi?')) return
    setBusy(certId)
    setError(null)
    try {
      await api.deleteCertificate(certId)
      setSuccess('Sertifika silindi')
      if (siteId) await loadCerts(siteId)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Silinemedi')
    } finally {
      setBusy(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Certificates</h2>
          <p className="empty-state">Let&apos;s Encrypt (ACME HTTP-01) — port 80 açık olmalı</p>
        </div>
      </div>

      {error && <p className="error-banner">{error}</p>}
      {success && <p className="success-banner">{success}</p>}

      <div className="card form-grid">
        <label>
          Site
          <select value={siteId} onChange={(e) => setSiteId(e.target.value)}>
            {sites.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} ({parseHosts(s.hosts).join(', ')})
              </option>
            ))}
          </select>
        </label>
        <label>
          Domain
          <input value={domain} onChange={(e) => setDomain(e.target.value)} placeholder="example.com" />
        </label>
        <label>
          ACME Email (opsiyonel — BADSECTOR_ACME_EMAIL fallback)
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="admin@example.com" />
        </label>
        <label className="checkbox-row">
          <input type="checkbox" checked={autoRenew} onChange={(e) => setAutoRenew(e.target.checked)} />
          Otomatik yenileme
        </label>
        <div className="page-actions">
          <button type="button" disabled={!!busy || !domain.trim()} onClick={() => requestCert(false)}>
            Kaydet
          </button>
          <button type="button" className="primary" disabled={!!busy || !domain.trim()} onClick={() => requestCert(true)}>
            {busy === 'create' ? 'İşleniyor…' : "Let's Encrypt Al"}
          </button>
        </div>
      </div>

      <div className="card" style={{ marginTop: '1rem' }}>
        <h3>Sertifikalar</h3>
        {loading ? (
          <p className="empty-state">Yükleniyor…</p>
        ) : certs.length === 0 ? (
          <p className="empty-state">Henüz sertifika yok</p>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Domain</th>
                <th>Durum</th>
                <th>Bitiş</th>
                <th>Auto</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {certs.map((c) => (
                <tr key={c.id}>
                  <td>{c.domain}</td>
                  <td>
                    <span className={`status-pill ${statusClass[c.status] ?? 'down'}`}>{c.status}</span>
                    {c.last_error && <div className="empty-state">{c.last_error}</div>}
                  </td>
                  <td>{c.expires_at ? new Date(c.expires_at).toLocaleString() : '—'}</td>
                  <td>{c.auto_renew ? 'evet' : 'hayır'}</td>
                  <td className="page-actions">
                    {c.status !== 'active' && (
                      <button type="button" disabled={!!busy} onClick={() => issue(c.id)}>
                        Al
                      </button>
                    )}
                    <button type="button" disabled={!!busy} onClick={() => renew(c.id)}>
                      Yenile
                    </button>
                    <button type="button" disabled={!!busy} onClick={() => remove(c.id)}>
                      Sil
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ marginTop: '1rem' }}>
        <h3>Canlı sunucu checklist</h3>
        <ul className="empty-state" style={{ textAlign: 'left', lineHeight: 1.8 }}>
          <li>DNS A/AAAA kaydı sunucunuza işaret etmeli</li>
          <li><code>BADSECTOR_HAPROXY_CONFIG=live</code> ve port 80/443 açık</li>
          <li>Site hostnames domain ile eşleşmeli</li>
          <li>Staging test: <code>BADSECTOR_ACME_STAGING=true</code></li>
          <li>Sertifika sonrası: <code>docker compose restart haproxy</code></li>
        </ul>
      </div>
    </div>
  )
}
