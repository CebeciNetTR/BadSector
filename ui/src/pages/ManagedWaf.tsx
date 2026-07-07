import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, ApiError } from '../api/client'
import {
  defaultManagedWafConfig,
  PARANOIA_LEVELS,
  WAF_MODES,
  type ManagedWafConfig,
  type WafMode,
} from '../types/managedWaf'
import { parseHosts, type Site } from '../types/site'

export default function ManagedWaf() {
  const [searchParams] = useSearchParams()
  const initialSiteId = searchParams.get('site') ?? ''

  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState(initialSiteId)
  const [enabled, setEnabled] = useState(false)
  const [config, setConfig] = useState<ManagedWafConfig>(defaultManagedWafConfig())
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const loadWaf = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const data = await api.getManagedWaf(id)
      setEnabled(data.enabled)
      setConfig({ ...defaultManagedWafConfig(), ...data.config })
      setDirty(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'WAF ayarları yüklenemedi')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    async function init() {
      try {
        const list = await api.listSites()
        setSites(list)
        if (list.length > 0) {
          const preferred =
            initialSiteId && list.some((s) => s.id === initialSiteId)
              ? initialSiteId
              : list[0].id
          setSiteId(preferred)
        }
      } catch (err) {
        setError(err instanceof ApiError ? err.message : 'Siteler yüklenemedi')
        setLoading(false)
      }
    }
    init()
  }, [initialSiteId])

  useEffect(() => {
    if (siteId) loadWaf(siteId)
  }, [siteId, loadWaf])

  const updateConfig = (patch: Partial<ManagedWafConfig>) => {
    setConfig((c) => ({ ...c, ...patch }))
    setDirty(true)
    setSuccess(null)
  }

  const handleSave = async () => {
    if (!siteId) return
    setSaving(true)
    setError(null)
    setSuccess(null)
    try {
      await api.saveManagedWaf(siteId, { enabled, config })
      await api.reloadRuntime()
      setDirty(false)
      setSuccess('WAF ayarları kaydedildi. Pipeline\'da managed_waf modülü güncellendi.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Kaydetme başarısız')
    } finally {
      setSaving(false)
    }
  }

  const currentSite = sites.find((s) => s.id === siteId)

  return (
    <>
      <div className="page-header">
        <div>
          <h2>Managed WAF (Coraza)</h2>
          <p className="page-desc">
            Coraza tabanlı WAF modülü. Pipeline&apos;da rate limit sonrası, reverse proxy
            öncesinde çalışır. Ucuz filtrelerden sonra devreye girer.
          </p>
        </div>
        <div className="page-actions">
          {dirty && <span className="dirty-badge">Kaydedilmemiş değişiklikler</span>}
          <button
            type="button"
            className="btn btn-primary"
            disabled={!dirty || saving || !siteId}
            onClick={handleSave}
          >
            {saving ? 'Kaydediliyor…' : 'Kaydet ve Uygula'}
          </button>
        </div>
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {success && <div className="alert alert-success">{success}</div>}

      <div className="card toolbar">
        <label className="field" style={{ marginBottom: 0, minWidth: 280 }}>
          <span>Site</span>
          <select
            value={siteId}
            onChange={(e) => setSiteId(e.target.value)}
            disabled={sites.length === 0}
          >
            {sites.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name} ({parseHosts(site.hosts).join(', ')})
              </option>
            ))}
          </select>
        </label>
        <label className="toggle">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => { setEnabled(e.target.checked); setDirty(true) }}
          />
          <span>{enabled ? 'Modül aktif' : 'Modül pasif'}</span>
        </label>
        {currentSite && (
          <span className={`badge ${currentSite.enabled ? 'pass' : 'fail'}`}>
            Site {currentSite.enabled ? 'aktif' : 'pasif'}
          </span>
        )}
      </div>

      {loading ? (
        <div className="card"><p className="empty-state">Yükleniyor…</p></div>
      ) : (
        <div className="card">
          <h3>Coraza Ayarları</h3>
          <div className="form-grid" style={{ marginTop: '1rem' }}>
            <label className="field">
              <span>Ruleset</span>
              <input
                type="text"
                value={config.ruleset}
                onChange={(e) => updateConfig({ ruleset: e.target.value })}
              />
            </label>
            <label className="field">
              <span>Paranoia level</span>
              <select
                value={config.paranoia_level}
                onChange={(e) => updateConfig({ paranoia_level: Number(e.target.value) })}
              >
                {PARANOIA_LEVELS.map((p) => (
                  <option key={p.value} value={p.value}>{p.label}</option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Mod</span>
              <select
                value={config.mode}
                onChange={(e) => updateConfig({ mode: e.target.value as WafMode })}
              >
                {WAF_MODES.map((m) => (
                  <option key={m.value} value={m.value}>{m.label}</option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Audit log</span>
              <select
                value={config.audit ? 'yes' : 'no'}
                onChange={(e) => updateConfig({ audit: e.target.value === 'yes' })}
              >
                <option value="yes">Açık</option>
                <option value="no">Kapalı</option>
              </select>
            </label>
            <label className="field span-2">
              <span>Hariç tutulan path&apos;ler (virgülle ayırın)</span>
              <input
                type="text"
                value={config.exclude_paths.join(', ')}
                onChange={(e) =>
                  updateConfig({
                    exclude_paths: e.target.value.split(',').map((p) => p.trim()).filter(Boolean),
                  })
                }
              />
            </label>
            <label className="field span-2">
              <span>Coraza rules dizini</span>
              <input
                type="text"
                value={config.rules_dir}
                onChange={(e) => updateConfig({ rules_dir: e.target.value })}
              />
              <span className="field-hint">
                Production: CRS kuralları bu dizine mount edilir. Coraza yoksa built-in kurallar kullanılır.
              </span>
            </label>
          </div>
        </div>
      )}
    </>
  )
}
