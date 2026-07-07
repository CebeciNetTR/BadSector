import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, ApiError } from '../api/client'
import DeletePolicyModal from '../components/policies/DeletePolicyModal'
import PolicyForm from '../components/policies/PolicyForm'
import PolicyList from '../components/policies/PolicyList'
import {
  defaultPolicyForm,
  formToPolicyPayload,
  policyToForm,
  type Policy,
  type PolicyFormData,
} from '../types/policy'
import { parseHosts, type Site } from '../types/site'

export default function Policies() {
  const [searchParams] = useSearchParams()
  const initialSiteId = searchParams.get('site') ?? ''

  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState(initialSiteId)
  const [policies, setPolicies] = useState<Policy[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [isNew, setIsNew] = useState(false)
  const [form, setForm] = useState<PolicyFormData | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Policy | null>(null)
  const [deleting, setDeleting] = useState(false)

  const loadPolicies = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const list = await api.listPolicies(id)
      setPolicies(list)
      setSelectedId(null)
      setForm(null)
      setIsNew(false)
      setDirty(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Politikalar yüklenemedi')
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
    if (siteId) loadPolicies(siteId)
  }, [siteId, loadPolicies])

  const selectPolicy = (policy: Policy) => {
    setSelectedId(policy.id)
    setIsNew(false)
    setForm(policyToForm(policy))
    setDirty(false)
    setSuccess(null)
  }

  const startNewPolicy = () => {
    setSelectedId(null)
    setIsNew(true)
    setForm(defaultPolicyForm())
    setDirty(true)
    setSuccess(null)
  }

  const handleSelect = (id: string) => {
    if (dirty && !confirm('Kaydedilmemiş değişiklikler var. Devam edilsin mi?')) return
    const policy = policies.find((p) => p.id === id)
    if (policy) selectPolicy(policy)
  }

  const handleAdd = () => {
    if (dirty && !confirm('Kaydedilmemiş değişiklikler var. Devam edilsin mi?')) return
    startNewPolicy()
  }

  const handleToggle = async (id: string, enabled: boolean) => {
    const policy = policies.find((p) => p.id === id)
    if (!policy || !siteId) return
    const formData = policyToForm(policy)
    formData.enabled = enabled
    try {
      const updated = await api.updatePolicy(siteId, id, formToPolicyPayload(formData))
      await api.reloadRuntime()
      setPolicies((prev) => prev.map((p) => (p.id === updated.id ? updated : p)))
      if (selectedId === id) selectPolicy(updated)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Güncelleme başarısız')
    }
  }

  const validate = (): string | null => {
    if (!form?.name.trim()) return 'Politika adı zorunludur.'
    if (!form.conditions.rules.length) return 'En az bir koşul ekleyin.'
    if (!form.actions.length) return 'En az bir aksiyon ekleyin.'
    return null
  }

  const handleSave = async () => {
    if (!siteId || !form) return
    const validationError = validate()
    if (validationError) {
      setError(validationError)
      return
    }

    setSaving(true)
    setError(null)
    setSuccess(null)

    try {
      const payload = formToPolicyPayload(form)

      if (isNew) {
        const created = await api.createPolicy(siteId, payload)
        await api.reloadRuntime()
        setPolicies((prev) => [...prev, created].sort((a, b) => a.priority - b.priority))
        selectPolicy(created)
        setSuccess('Politika oluşturuldu.')
      } else if (selectedId) {
        const updated = await api.updatePolicy(siteId, selectedId, payload)
        await api.reloadRuntime()
        setPolicies((prev) =>
          prev.map((p) => (p.id === updated.id ? updated : p)).sort((a, b) => a.priority - b.priority),
        )
        selectPolicy(updated)
        setSuccess('Politika güncellendi.')
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Kaydetme başarısız')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!deleteTarget || !siteId) return
    setDeleting(true)
    setError(null)
    try {
      await api.deletePolicy(siteId, deleteTarget.id)
      await api.reloadRuntime()
      setPolicies((prev) => prev.filter((p) => p.id !== deleteTarget.id))
      setDeleteTarget(null)
      setSuccess(`"${deleteTarget.name}" silindi.`)
      setSelectedId(null)
      setForm(null)
      setIsNew(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Silme başarısız')
    } finally {
      setDeleting(false)
    }
  }

  const currentSite = sites.find((s) => s.id === siteId)

  return (
    <>
      <div className="page-header">
        <div>
          <h2>Politikalar</h2>
          <p className="page-desc">
            Koşul ve aksiyon tabanlı güvenlik kuralları. Öncelik sırasına göre değerlendirilir.
            Nginx syntax gerekmez.
          </p>
        </div>
        <div className="page-actions">
          {dirty && <span className="dirty-badge">Kaydedilmemiş değişiklikler</span>}
          <button
            type="button"
            className="btn btn-primary"
            disabled={!dirty || saving || !form}
            onClick={handleSave}
          >
            {saving ? 'Kaydediliyor…' : isNew ? 'Politika Oluştur' : 'Kaydet'}
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
          <PolicyList
            policies={policies}
            selectedId={isNew ? null : selectedId}
            onSelect={handleSelect}
            onAdd={handleAdd}
            onDelete={setDeleteTarget}
            onToggle={handleToggle}
          />
          <PolicyForm
            form={form}
            onChange={(f) => { setForm(f); setDirty(true) }}
          />
        </div>
      )}

      {deleteTarget && (
        <DeletePolicyModal
          policyName={deleteTarget.name}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          deleting={deleting}
        />
      )}
    </>
  )
}
