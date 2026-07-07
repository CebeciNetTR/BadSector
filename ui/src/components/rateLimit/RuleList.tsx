import { KEY_BY_LABELS, type RateLimitRule } from '../../types/rateLimit'

interface Props {
  rules: RateLimitRule[]
  selectedId: string | null
  onSelect: (id: string) => void
  onAdd: () => void
  onDelete: (id: string) => void
  onToggle: (id: string, enabled: boolean) => void
}

export default function RuleList({
  rules,
  selectedId,
  onSelect,
  onAdd,
  onDelete,
  onToggle,
}: Props) {
  return (
    <div className="card">
      <div className="card-header">
        <h3>Kurallar</h3>
        <button type="button" className="btn btn-primary" onClick={onAdd}>
          + Kural ekle
        </button>
      </div>

      {rules.length === 0 ? (
        <p className="empty-state">
          Henüz rate limit kuralı yok. İlk kuralınızı ekleyerek başlayın.
        </p>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Durum</th>
                <th>Ad</th>
                <th>Anahtar</th>
                <th>Limit</th>
                <th>Pencere</th>
                <th>Path</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {rules.map((rule) => (
                <tr
                  key={rule.id}
                  className={selectedId === rule.id ? 'selected' : ''}
                  onClick={() => onSelect(rule.id)}
                >
                  <td>
                    <label className="toggle compact" onClick={(e) => e.stopPropagation()}>
                      <input
                        type="checkbox"
                        checked={rule.enabled}
                        onChange={(e) => onToggle(rule.id, e.target.checked)}
                      />
                    </label>
                  </td>
                  <td>
                    <strong>{rule.name || 'İsimsiz kural'}</strong>
                  </td>
                  <td>{KEY_BY_LABELS[rule.key_by] ?? rule.key_by}</td>
                  <td>
                    {rule.limit}
                    {rule.burst > 0 && (
                      <span className="muted-inline"> +{rule.burst} burst</span>
                    )}
                  </td>
                  <td>{formatWindow(rule.window)}</td>
                  <td className="mono">{rule.paths?.join(', ') || '/*'}</td>
                  <td>
                    <button
                      type="button"
                      className="btn btn-danger btn-sm"
                      onClick={(e) => {
                        e.stopPropagation()
                        onDelete(rule.id)
                      }}
                    >
                      Sil
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function formatWindow(window: string | number): string {
  const w = String(window)
  if (w === '1m') return '1 dk'
  if (w === '5m') return '5 dk'
  if (w === '1h') return '1 saat'
  if (w.endsWith('s')) return w.replace('s', ' sn')
  return w
}
