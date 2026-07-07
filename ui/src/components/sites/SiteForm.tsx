import type { SiteFormData } from '../../types/site'
import { DEFAULT_BACKEND_URL, inputToHosts } from '../../types/site'

interface Props {
  form: SiteFormData
  hostsInput: string
  isNew: boolean
  onChange: (form: SiteFormData) => void
  onHostsInputChange: (value: string) => void
}

export default function SiteForm({
  form,
  hostsInput,
  isNew,
  onChange,
  onHostsInputChange,
}: Props) {
  const update = (patch: Partial<SiteFormData>) => {
    onChange({ ...form, ...patch })
  }

  const updateSettings = (patch: Partial<SiteFormData['settings']>) => {
    onChange({ ...form, settings: { ...form.settings, ...patch } })
  }

  return (
    <div className="card">
      <h3>{isNew ? 'Yeni Site' : 'Site Düzenle'}</h3>

      <div className="form-grid" style={{ marginTop: '1rem' }}>
        <label className="field span-2">
          <span>Site adı</span>
          <input
            type="text"
            placeholder="Örn: Production API"
            value={form.name}
            onChange={(e) => update({ name: e.target.value })}
          />
        </label>

        <label className="field span-2">
          <span>Hostnames (satır veya virgülle ayırın)</span>
          <textarea
            rows={4}
            placeholder={'api.example.com\nwww.example.com'}
            value={hostsInput}
            onChange={(e) => {
              onHostsInputChange(e.target.value)
              update({ hosts: inputToHosts(e.target.value) })
            }}
          />
        </label>

        <label className="field span-2">
          <span>Backend URL (upstream)</span>
          <input
            type="text"
            placeholder={DEFAULT_BACKEND_URL}
            value={form.backend_url}
            onChange={(e) => update({ backend_url: e.target.value })}
          />
          <span className="field-hint">
            reverse_proxy modülünün yönlendireceği origin adresi
          </span>
        </label>

        <label className="field span-2">
          <span>Canonical URL (edge yönlendirme)</span>
          <select
            value={form.settings.canonical_host ?? 'none'}
            onChange={(e) =>
              updateSettings({
                canonical_host: e.target.value as SiteFormData['settings']['canonical_host'],
              })
            }
          >
            <option value="none">Yok — gelen Host ile açılır</option>
            <option value="www">Her zaman www (301 → https://www…)</option>
            <option value="apex">Her zaman apex / wwwsiz (301 → https://domain…)</option>
          </select>
          <span className="field-hint">
            Ziyaretçi yanlış hostname ile gelirse BadSector edge 301 ile canonical adrese yönlendirir.
            Hosts listesinde hem apex hem www tanımlı olmalı.
          </span>
        </label>

        <label className="field">
          <select
            value={form.enabled ? 'enabled' : 'disabled'}
            onChange={(e) => update({ enabled: e.target.value === 'enabled' })}
          >
            <option value="enabled">Aktif</option>
            <option value="disabled">Pasif</option>
          </select>
        </label>

        <label className="field">
          <span>Debug trace</span>
          <select
            value={form.settings.debug_trace ? 'yes' : 'no'}
            onChange={(e) => updateSettings({ debug_trace: e.target.value === 'yes' })}
          >
            <option value="no">Kapalı</option>
            <option value="yes">Açık — X-BadSector-Trace header</option>
          </select>
        </label>
      </div>

      <div className="rule-preview" style={{ marginTop: '1rem' }}>
        <span className="preview-label">Özet</span>
        <code>
          {form.name || 'İsimsiz site'} → {form.hosts.length} hostname →{' '}
          {form.backend_url || DEFAULT_BACKEND_URL}
          {form.settings.canonical_host && form.settings.canonical_host !== 'none'
            ? ` · canonical: ${form.settings.canonical_host}`
            : ''}
          {form.enabled ? ' · aktif' : ' · pasif'}
        </code>
      </div>
    </div>
  )
}
