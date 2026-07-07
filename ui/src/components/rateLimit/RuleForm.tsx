import {
  HTTP_METHODS,
  KEY_BY_LABELS,
  WINDOW_PRESETS,
  type KeyBy,
  type RateLimitRule,
} from '../../types/rateLimit'

interface Props {
  rule: RateLimitRule | null
  onChange: (rule: RateLimitRule) => void
}

export default function RuleForm({ rule, onChange }: Props) {
  if (!rule) {
    return (
      <div className="card">
        <p className="empty-state">
          Düzenlemek için listeden bir kural seçin veya yeni kural ekleyin.
        </p>
      </div>
    )
  }

  const update = (patch: Partial<RateLimitRule>) => {
    onChange({ ...rule, ...patch })
  }

  const toggleMethod = (method: string) => {
    const methods = rule.methods ?? []
    const next = methods.includes(method)
      ? methods.filter((m) => m !== method)
      : [...methods, method]
    update({ methods: next })
  }

  return (
    <div className="card">
      <h3>Kural Düzenle</h3>

      <div className="form-grid">
        <label className="field span-2">
          <span>Kural adı</span>
          <input
            type="text"
            placeholder="Örn: Global IP limiti"
            value={rule.name}
            onChange={(e) => update({ name: e.target.value })}
          />
        </label>

        <label className="field">
          <span>Anahtar stratejisi</span>
          <select
            value={rule.key_by}
            onChange={(e) => update({ key_by: e.target.value as KeyBy })}
          >
            {(Object.entries(KEY_BY_LABELS) as [KeyBy, string][]).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>

        {rule.key_by === 'header' && (
          <label className="field">
            <span>Header adı</span>
            <input
              type="text"
              placeholder="Authorization"
              value={rule.header_name ?? ''}
              onChange={(e) => update({ header_name: e.target.value })}
            />
          </label>
        )}

        {rule.key_by === 'cookie' && (
          <label className="field">
            <span>Cookie adı</span>
            <input
              type="text"
              placeholder="session"
              value={rule.cookie_name ?? ''}
              onChange={(e) => update({ cookie_name: e.target.value })}
            />
          </label>
        )}

        <label className="field">
          <span>Limit (istek)</span>
          <input
            type="number"
            min={1}
            value={rule.limit}
            onChange={(e) => update({ limit: Number(e.target.value) })}
          />
        </label>

        <label className="field">
          <span>Burst</span>
          <input
            type="number"
            min={0}
            value={rule.burst}
            onChange={(e) => update({ burst: Number(e.target.value) })}
          />
        </label>

        <label className="field">
          <span>Zaman penceresi</span>
          <select
            value={String(rule.window)}
            onChange={(e) => update({ window: e.target.value })}
          >
            {WINDOW_PRESETS.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
        </label>

        <label className="field span-2">
          <span>Path desenleri (virgülle ayırın)</span>
          <input
            type="text"
            placeholder="/*, /api/*"
            value={(rule.paths ?? []).join(', ')}
            onChange={(e) =>
              update({
                paths: e.target.value
                  .split(',')
                  .map((p) => p.trim())
                  .filter(Boolean),
              })
            }
          />
        </label>
      </div>

      <div className="field" style={{ marginTop: '1rem' }}>
        <span>HTTP metodları (boş = tümü)</span>
        <div className="chip-group">
          {HTTP_METHODS.map((method) => (
            <button
              key={method}
              type="button"
              className={`chip ${(rule.methods ?? []).includes(method) ? 'active' : ''}`}
              onClick={() => toggleMethod(method)}
            >
              {method}
            </button>
          ))}
        </div>
      </div>

      <div className="rule-preview">
        <span className="preview-label">Özet</span>
        <code>
          {KEY_BY_LABELS[rule.key_by]} → max {rule.limit + rule.burst} istek /{' '}
          {formatWindow(rule.window)} — paths: {(rule.paths ?? ['/*']).join(', ')}
        </code>
      </div>
    </div>
  )
}

function formatWindow(window: string | number): string {
  const w = String(window)
  if (w === '1m') return '1dk'
  if (w === '5m') return '5dk'
  if (w === '1h') return '1sa'
  return w
}
