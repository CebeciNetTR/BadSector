import { useEffect, useState } from 'react'
import { api, ApiError } from '../api/client'
import DeleteSiteModal from '../components/sites/DeleteSiteModal'
import PipelineSummary from '../components/sites/PipelineSummary'
import SiteForm from '../components/sites/SiteForm'
import SiteList from '../components/sites/SiteList'
import {
  defaultSiteForm,
  formToPayload,
  hostsToInput,
  siteToForm,
  type PipelineStage,
  type Site,
  type SiteFormData,
} from '../types/site'

export default function Sites() {
  const [sites, setSites] = useState<Site[]>([])
  const [pipeline, setPipeline] = useState<PipelineStage[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [isNew, setIsNew] = useState(false)
  const [form, setForm] = useState<SiteFormData>(defaultSiteForm())
  const [hostsInput, setHostsInput] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Site | null>(null)
  const [deleting, setDeleting] = useState(false)

  const loadSiteDetail = async (site: Site) => {
    try {
      const detail = await api.getSite(site.id)
      setPipeline(detail.pipeline ?? [])
      const formData = siteToForm(site, detail.pipeline ?? [])
      setForm(formData)
      setHostsInput(hostsToInput(formData.hosts))
    } catch {
      setPipeline([])
      const formData = siteToForm(site)
      setForm(formData)
      setHostsInput(hostsToInput(formData.hosts))
    }
  }

  useEffect(() => {
    async function init() {
      setLoading(true)
      setError(null)
      try {
        const list = await api.listSites()
        setSites(list)
        if (list.length > 0) {
          const site = list[0]
          setSelectedId(site.id)
          setIsNew(false)
          await loadSiteDetail(site)
          setDirty(false)
        } else {
          setIsNew(true)
          setForm(defaultSiteForm())
          setHostsInput('')
          setPipeline([])
          setDirty(true)
        }
      } catch (err) {
        setError(err instanceof ApiError ? err.message : 'Siteler yüklenemedi')
      } finally {
        setLoading(false)
      }
    }
    init()
  }, [])

  const selectSite = async (site: Site) => {
    setSelectedId(site.id)
    setIsNew(false)
    await loadSiteDetail(site)
    setDirty(false)
    setSuccess(null)
  }

  const startNewSite = () => {
    setSelectedId(null)
    setIsNew(true)
    setForm(defaultSiteForm())
    setHostsInput('')
    setPipeline([])
    setDirty(true)
    setSuccess(null)
  }

  const handleSelect = async (id: string) => {
    if (dirty && !confirm('Kaydedilmemiş değişiklikler var. Devam edilsin mi?')) {
      return
    }
    const site = sites.find((s) => s.id === id)
    if (site) await selectSite(site)
  }

  const handleAdd = () => {
    if (dirty && !confirm('Kaydedilmemiş değişiklikler var. Devam edilsin mi?')) {
      return
    }
    startNewSite()
  }

  const validate = (): string | null => {
    if (!form.name.trim()) return 'Site adı zorunludur.'
    if (form.hosts.length === 0) return 'En az bir hostname girin.'
    if (!form.backend_url.trim()) return 'Backend URL zorunludur.'
    return null
  }

  const handleSave = async () => {
    const validationError = validate()
    if (validationError) {
      setError(validationError)
      return
    }

    setSaving(true)
    setError(null)
    setSuccess(null)

    try {
      const payload = formToPayload(form)

      if (isNew) {
        const created = await api.createSite(payload)
        await api.reloadRuntime()
        setSites((prev) => [...prev, created])
        await selectSite(created)
        setSuccess('Site oluşturuldu ve varsayılan pipeline atandı.')
      } else if (selectedId) {
        const updated = await api.updateSite(selectedId, payload)
        await api.reloadRuntime()
        setSites((prev) => prev.map((s) => (s.id === updated.id ? updated : s)))
        await selectSite(updated)
        setSuccess('Site güncellendi.')
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Kaydetme başarısız')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    setDeleting(true)
    setError(null)
    try {
      await api.deleteSite(deleteTarget.id)
      await api.reloadRuntime()
      setDeleteTarget(null)
      setSuccess(`"${deleteTarget.name}" silindi.`)
      const remaining = sites.filter((s) => s.id !== deleteTarget.id)
      setSites(remaining)
      if (remaining.length > 0) {
        await selectSite(remaining[0])
      } else {
        startNewSite()
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Silme başarısız')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <>
      <div className="page-header">
        <div>
          <h2>Siteler</h2>
          <p className="page-desc">
            Hostname bazlı site yapılandırması. Her site kendi pipeline, politika ve rate
            limit kurallarına sahiptir. Nginx syntax gerekmez.
          </p>
        </div>
        <div className="page-actions">
          {dirty && <span className="dirty-badge">Kaydedilmemiş değişiklikler</span>}
          <button
            type="button"
            className="btn btn-primary"
            disabled={!dirty || saving}
            onClick={handleSave}
          >
            {saving ? 'Kaydediliyor…' : isNew ? 'Site Oluştur' : 'Kaydet'}
          </button>
        </div>
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {success && <div className="alert alert-success">{success}</div>}

      {loading ? (
        <div className="card">
          <p className="empty-state">Yükleniyor…</p>
        </div>
      ) : (
        <>
          <div className="split-layout">
            <SiteList
              sites={sites}
              selectedId={isNew ? null : selectedId}
              onSelect={handleSelect}
              onAdd={handleAdd}
              onDelete={setDeleteTarget}
            />
            <SiteForm
              form={form}
              hostsInput={hostsInput}
              isNew={isNew}
              onChange={(f) => { setForm(f); setDirty(true) }}
              onHostsInputChange={setHostsInput}
            />
          </div>
          {!isNew && selectedId && pipeline.length > 0 && (
            <PipelineSummary stages={pipeline} />
          )}
        </>
      )}

      {deleteTarget && (
        <DeleteSiteModal
          siteName={deleteTarget.name}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          deleting={deleting}
        />
      )}
    </>
  )
}
