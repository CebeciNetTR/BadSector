import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, ApiError } from '../api/client'
import AddModulePanel from '../components/pipeline/AddModulePanel'
import PipelineEditor from '../components/pipeline/PipelineEditor'
import {
  addModule,
  availableModules,
  ensureReverseProxy,
  stagesFromApi,
  stagesToPayload,
  type EditablePipelineStage,
} from '../types/pipeline'
import { parseHosts, type Site } from '../types/site'

export default function PipelinePage() {
  const [searchParams] = useSearchParams()
  const initialSiteId = searchParams.get('site') ?? ''

  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState(initialSiteId)
  const [stages, setStages] = useState<EditablePipelineStage[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const loadPipeline = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const list = await api.getPipeline(id)
      setStages(ensureReverseProxy(stagesFromApi(list)))
      setDirty(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Pipeline yüklenemedi')
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
    if (siteId) loadPipeline(siteId)
  }, [siteId, loadPipeline])

  const handleChange = (next: EditablePipelineStage[]) => {
    setStages(ensureReverseProxy(next))
    setDirty(true)
    setSuccess(null)
  }

  const handleAddModule = (module: string) => {
    handleChange(addModule(stages, module))
  }

  const handleSave = async () => {
    if (!siteId) return
    setSaving(true)
    setError(null)
    setSuccess(null)
    try {
      const payload = ensureReverseProxy(stages)
      await api.updatePipeline(siteId, stagesToPayload(payload))
      await api.reloadRuntime()
      await loadPipeline(siteId)
      setSuccess('Pipeline kaydedildi ve runtime yenilendi.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Kaydetme başarısız')
    } finally {
      setSaving(false)
    }
  }

  const handleReset = async () => {
    if (!siteId) return
    if (dirty && !confirm('Kaydedilmemiş değişiklikler silinecek. Devam edilsin mi?')) return
    await loadPipeline(siteId)
  }

  const currentSite = sites.find((s) => s.id === siteId)
  const addable = availableModules(stages)

  return (
    <>
      <div className="page-header">
        <div>
          <h2>Pipeline</h2>
          <p className="page-desc">
            Modülleri sürükleyerek sıralayın, aktif/pasif yapın veya yeni modül ekleyin.
            reverse_proxy her zaman sonda kalır. Değişiklikler nginx reload gerektirmez.
          </p>
        </div>
        <div className="page-actions">
          {dirty && <span className="dirty-badge">Kaydedilmemiş değişiklikler</span>}
          <button type="button" className="btn" disabled={!dirty || saving} onClick={handleReset}>
            Sıfırla
          </button>
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
            onChange={(e) => {
              if (dirty && !confirm('Kaydedilmemiş değişiklikler var. Devam edilsin mi?')) return
              setSiteId(e.target.value)
            }}
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
          <span className={`badge ${currentSite.enabled ? 'pass' : 'fail'}`}>
            {currentSite.enabled ? 'Aktif' : 'Pasif'}
          </span>
        )}
      </div>

      {loading ? (
        <div className="card">
          <p className="empty-state">Yükleniyor…</p>
        </div>
      ) : sites.length === 0 ? (
        <div className="card">
          <p className="empty-state">
            Henüz site yok. Önce <strong>Siteler</strong> bölümünden bir site oluşturun.
          </p>
        </div>
      ) : (
        <div className="split-layout">
          <div className="card">
            <h3 style={{ marginBottom: '1rem' }}>Modül Sırası</h3>
            <PipelineEditor stages={stages} onChange={handleChange} />
          </div>
          <AddModulePanel available={addable} onAdd={handleAddModule} />
        </div>
      )}
    </>
  )
}
