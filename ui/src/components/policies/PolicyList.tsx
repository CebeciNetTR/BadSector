import type { Policy } from '../../types/policy'
import {
  summarizeActions,
  summarizeConditions,
  parseActions,
  parseConditions,
} from '../../types/policy'

interface Props {
  policies: Policy[]
  selectedId: string | null
  onSelect: (id: string) => void
  onAdd: () => void
  onDelete: (policy: Policy) => void
  onToggle: (id: string, enabled: boolean) => void
}

export default function PolicyList({
  policies,
  selectedId,
  onSelect,
  onAdd,
  onDelete,
  onToggle,
}: Props) {
  return (
    <div className="card">
      <div className="card-header">
        <h3>Politikalar</h3>
        <button type="button" className="btn btn-primary" onClick={onAdd}>
          + Politika ekle
        </button>
      </div>

      {policies.length === 0 ? (
        <p className="empty-state">Henüz politika yok. İlk politikanızı ekleyin.</p>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Durum</th>
                <th>Öncelik</th>
                <th>Ad</th>
                <th>Koşullar</th>
                <th>Aksiyonlar</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {policies.map((policy) => {
                const conditions = parseConditions(policy.conditions)
                const actions = parseActions(policy.actions)
                return (
                  <tr
                    key={policy.id}
                    className={selectedId === policy.id ? 'selected' : ''}
                    onClick={() => onSelect(policy.id)}
                  >
                    <td>
                      <label className="toggle compact" onClick={(e) => e.stopPropagation()}>
                        <input
                          type="checkbox"
                          checked={policy.enabled}
                          onChange={(e) => onToggle(policy.id, e.target.checked)}
                        />
                      </label>
                    </td>
                    <td className="mono">{policy.priority}</td>
                    <td><strong>{policy.name}</strong></td>
                    <td className="muted-inline">{summarizeConditions(conditions)}</td>
                    <td className="muted-inline">{summarizeActions(actions)}</td>
                    <td>
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        onClick={(e) => {
                          e.stopPropagation()
                          onDelete(policy)
                        }}
                      >
                        Sil
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
