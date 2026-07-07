import {
  ACTION_TYPE_LABELS,
  CONDITION_TYPE_LABELS,
  OPERATOR_LABELS,
  type ActionType,
  type ConditionOperator,
  type ConditionType,
  type PolicyAction,
  type PolicyFormData,
  type PolicyCondition,
} from '../../types/policy'

interface Props {
  form: PolicyFormData | null
  onChange: (form: PolicyFormData) => void
}

const CONDITION_TYPES = Object.keys(CONDITION_TYPE_LABELS) as ConditionType[]
const OPERATORS = Object.keys(OPERATOR_LABELS) as ConditionOperator[]
const ACTION_TYPES = Object.keys(ACTION_TYPE_LABELS) as ActionType[]

export default function PolicyForm({ form, onChange }: Props) {
  if (!form) {
    return (
      <div className="card">
        <p className="empty-state">
          Düzenlemek için listeden bir politika seçin veya yeni politika ekleyin.
        </p>
      </div>
    )
  }

  const update = (patch: Partial<PolicyFormData>) => {
    onChange({ ...form, ...patch })
  }

  const updateCondition = (index: number, patch: Partial<PolicyCondition>) => {
    const rules = [...form.conditions.rules]
    rules[index] = { ...rules[index], ...patch }
    onChange({ ...form, conditions: { ...form.conditions, rules } })
  }

  const addCondition = () => {
    onChange({
      ...form,
      conditions: {
        ...form.conditions,
        rules: [...form.conditions.rules, { type: 'path', operator: 'prefix', value: '/' }],
      },
    })
  }

  const removeCondition = (index: number) => {
    onChange({
      ...form,
      conditions: {
        ...form.conditions,
        rules: form.conditions.rules.filter((_, i) => i !== index),
      },
    })
  }

  const updateAction = (index: number, patch: Partial<PolicyAction>) => {
    const actions = [...form.actions]
    actions[index] = { ...actions[index], ...patch }
    onChange({ ...form, actions })
  }

  const addAction = () => {
    onChange({ ...form, actions: [...form.actions, { type: 'continue' }] })
  }

  const removeAction = (index: number) => {
    onChange({ ...form, actions: form.actions.filter((_, i) => i !== index) })
  }

  return (
    <div className="card">
      <h3>Politika Düzenle</h3>

      <div className="form-grid" style={{ marginTop: '1rem' }}>
        <label className="field span-2">
          <span>Politika adı</span>
          <input
            type="text"
            placeholder="Örn: Admin geo block"
            value={form.name}
            onChange={(e) => update({ name: e.target.value })}
          />
        </label>

        <label className="field">
          <span>Öncelik (düşük = önce)</span>
          <input
            type="number"
            min={1}
            value={form.priority}
            onChange={(e) => update({ priority: Number(e.target.value) })}
          />
        </label>

        <label className="field">
          <span>Durum</span>
          <select
            value={form.enabled ? 'enabled' : 'disabled'}
            onChange={(e) => update({ enabled: e.target.value === 'enabled' })}
          >
            <option value="enabled">Aktif</option>
            <option value="disabled">Pasif</option>
          </select>
        </label>
      </div>

      <div className="section-block">
        <div className="section-header">
          <h4>Koşullar</h4>
          <select
            value={form.conditions.operator}
            onChange={(e) =>
              onChange({
                ...form,
                conditions: {
                  ...form.conditions,
                  operator: e.target.value as 'and' | 'or',
                },
              })
            }
          >
            <option value="and">Tümü (AND)</option>
            <option value="or">Herhangi biri (OR)</option>
          </select>
        </div>

        {form.conditions.rules.map((rule, index) => (
          <div key={index} className="rule-row">
            <select
              value={rule.type}
              onChange={(e) => updateCondition(index, { type: e.target.value as ConditionType })}
            >
              {CONDITION_TYPES.map((t) => (
                <option key={t} value={t}>{CONDITION_TYPE_LABELS[t]}</option>
              ))}
            </select>
            <select
              value={rule.operator}
              onChange={(e) =>
                updateCondition(index, { operator: e.target.value as ConditionOperator })
              }
            >
              {OPERATORS.map((op) => (
                <option key={op} value={op}>{OPERATOR_LABELS[op]}</option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Değer"
              value={String(rule.value ?? '')}
              onChange={(e) => updateCondition(index, { value: e.target.value })}
            />
            <button type="button" className="btn btn-sm" onClick={() => removeCondition(index)}>
              ✕
            </button>
          </div>
        ))}
        <button type="button" className="btn btn-sm" onClick={addCondition}>
          + Koşul ekle
        </button>
      </div>

      <div className="section-block">
        <div className="section-header">
          <h4>Aksiyonlar</h4>
        </div>

        {form.actions.map((action, index) => (
          <div key={index} className="rule-row">
            <select
              value={action.type}
              onChange={(e) => updateAction(index, { type: e.target.value as ActionType })}
            >
              {ACTION_TYPES.map((t) => (
                <option key={t} value={t}>{ACTION_TYPE_LABELS[t]}</option>
              ))}
            </select>

            {(action.type === 'block' || action.type === 'redirect') && (
              <input
                type="text"
                placeholder={action.type === 'redirect' ? 'URL' : 'Body (opsiyonel)'}
                value={action.url ?? action.body ?? ''}
                onChange={(e) =>
                  updateAction(
                    index,
                    action.type === 'redirect'
                      ? { url: e.target.value }
                      : { body: e.target.value },
                  )
                }
              />
            )}

            {action.type === 'log' && (
              <input
                type="text"
                placeholder="Log mesajı"
                value={action.message ?? ''}
                onChange={(e) => updateAction(index, { message: e.target.value })}
              />
            )}

            <button type="button" className="btn btn-sm" onClick={() => removeAction(index)}>
              ✕
            </button>
          </div>
        ))}
        <button type="button" className="btn btn-sm" onClick={addAction}>
          + Aksiyon ekle
        </button>
      </div>
    </div>
  )
}
