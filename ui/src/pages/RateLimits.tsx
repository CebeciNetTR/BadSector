import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, ApiError } from '../api/client'
import ModuleSettings from '../components/rateLimit/ModuleSettings'
import RuleForm from '../components/rateLimit/RuleForm'
import RuleList from '../components/rateLimit/RuleList'
import {
  defaultRateLimitConfig,
  defaultRule,
  type RateLimitConfig,
  type RateLimitRule,
} from '../types/rateLimit'
import { parseHosts, type Site } from '../types/site'

export default function RateLimits() {
  const [searchParams] = useSearchParams()
  const initialSiteId = searchParams.get('site') ?? ''

  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState<string>(initialSiteId)
  const [enabled, setEnabled] = useState(true)
  const [config, setConfig] = useState<RateLimitConfig>(defaultRateLimitConfig())
  const [selectedRuleId, setSelectedRuleId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const selectedRule = config.rules.find((r) => r.id === selectedRuleId) ?? null

  const loadSites = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const list = await api.listSites()
      setSites(list)
      if (list.length > 0) {
        const preferred = initialSiteId && list.some((s) => s.id === initialSiteId)
          ? initialSiteId
          : list[0].id
        setSiteId((current) => current || preferred)
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Siteler yüklenemedi')
    } finally {
      setLoading(false)
    }
  }, [initialSiteId])

  const loadRateLimits = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const data = await api.getRateLimits(id)
      setEnabled(data.enabled)
      setConfig({
        ...defaultRateLimitConfig(),
        ...data.config,
        redis: { ...defaultRateLimitConfig().redis, ...data.config?.redis },
        rules: data.config?.rules ?? [],
      })
      setSelectedRuleId(null)
      setDirty(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Rate limit ayarları yüklenemedi')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadSites()
  }, [loadSites])

  useEffect(() => {
    if (siteId) loadRateLimits(siteId)
  }, [siteId, loadRateLimits])

  const markDirty = () => setDirty(true)

  const handleAddRule = () => {
    const rule = defaultRule()
    setConfig((c) => ({ ...c, rules: [...c.rules, rule] }))
    setSelectedRuleId(rule.id)
    markDirty()
  }

  const handleDeleteRule = (id: string) => {
    setConfig((c) => ({ ...c, rules: c.rules.filter((r) => r.id !== id) }))
    if (selectedRuleId === id) setSelectedRuleId(null)
    markDirty()
  }

  const handleToggleRule = (id: string, ruleEnabled: boolean) => {
    setConfig((c) => ({
      ...c,
      rules: c.rules.map((r) => (r.id === id ? { ...r, enabled: ruleEnabled } : r)),
    }))
    markDirty()
  }

  const handleRuleChange = (rule: RateLimitRule) => {
    setConfig((c) => ({
      ...c,
      rules: c.rules.map((r) => (r.id === rule.id ? rule : r)),
    }))
    markDirty()
  }

  const handleSave = async () => {
    if (!siteId) return
    setSaving(true)
    setError(null)
    setSuccess(null)
    try {
      await api.saveRateLimits(siteId, { enabled, config })
      await api.reloadRuntime()
      setDirty(false)
      setSuccess('Ayarlar kaydedildi ve runtime yenilendi.')
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
          <h2>Rate Limit Yönetimi</h2>
          <p className="page-desc">
            Site bazlı rate limit kurallarını yapılandırın. Değişiklikler nginx reload
            gerektirmez — canlı uygulanır.
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
            {sites.length === 0 ? (
              <option value="">Site bulunamadı</option>
            ) : (
              sites.map((site) => (
                <option key={site.id} value={site.id}>
                  {site.name} ({parseHosts(site.hosts).join(', ') || site.id})
                </option>
              ))
            )}
          </select>
        </label>
        {currentSite && (
          <div className="site-meta">
            <span className={currentSite.enabled ? 'badge pass' : 'badge fail'}>
              {currentSite.enabled ? 'Aktif' : 'Pasif'}
            </span>
          </div>
        )}
      </div>

      {loading ? (
        <div className="card">
          <p className="empty-state">Yükleniyor…</p>
        </div>
      ) : sites.length === 0 ? (
        <div className="card">
          <p className="empty-state">
            Henüz site yok. Önce <strong>Sites</strong> bölümünden bir site oluşturun.
          </p>
        </div>
      ) : (
        <>
          <ModuleSettings
            enabled={enabled}
            config={config}
            onEnabledChange={(v) => { setEnabled(v); markDirty() }}
            onConfigChange={(c) => { setConfig(c); markDirty() }}
          />

          <div className="split-layout">
            <RuleList
              rules={config.rules}
              selectedId={selectedRuleId}
              onSelect={setSelectedRuleId}
              onAdd={handleAddRule}
              onDelete={handleDeleteRule}
              onToggle={handleToggleRule}
            />
            <RuleForm rule={selectedRule} onChange={handleRuleChange} />
          </div>
        </>
      )}
    </>
  )
}
