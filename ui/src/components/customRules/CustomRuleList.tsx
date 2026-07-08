import type { CustomRule } from '../../types/securityModules'

interface Props {
  rules: CustomRule[]
  selectedId: string | null
  onSelect: (id: string) => void
}

export default function CustomRuleList({ rules, selectedId, onSelect }: Props) {
  if (rules.length === 0) {
    return (
      <div className="card">
        <p className="empty-state">Henüz kural yok. Şablon veya yeni kural ekleyin.</p>
      </div>
    )
  }

  return (
    <div className="card">
      <h3>Kurallar ({rules.length})</h3>
      <ul className="rule-list">
        {rules.map((rule) => (
          <li key={rule.id}>
            <button
              type="button"
              className={`rule-list-item${selectedId === rule.id ? ' selected' : ''}`}
              onClick={() => onSelect(rule.id)}
            >
              <span className="rule-list-name">{rule.name}</span>
              <span className={`badge ${rule.enabled !== false ? 'badge-ok' : 'badge-muted'}`}>
                {rule.enabled !== false ? 'Aktif' : 'Pasif'}
              </span>
              <code className="rule-list-expr">{rule.match.expr ?? '—'}</code>
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
