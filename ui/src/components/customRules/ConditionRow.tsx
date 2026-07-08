import {
  OPERATOR_LABELS,
  OPERATORS_BY_FIELD,
  RULE_FIELD_HINTS,
  RULE_FIELD_LABELS,
  newCondition,
  type RuleField,
  type RuleOperator,
  type VisualCondition,
} from '../../types/customRuleBuilder'

interface Props {
  condition: VisualCondition
  onChange: (c: VisualCondition) => void
  onRemove: () => void
  canRemove: boolean
}

export default function ConditionRow({ condition, onChange, onRemove, canRemove }: Props) {
  const operators = OPERATORS_BY_FIELD[condition.field]
  const needsValue = !['is_true', 'is_false'].includes(condition.operator)
  const isList = ['in_list', 'not_in_list'].includes(condition.operator)

  const setField = (field: RuleField) => {
    const ops = OPERATORS_BY_FIELD[field]
    const operator = ops.includes(condition.operator) ? condition.operator : ops[0]
    onChange({ ...condition, field, operator, headerName: field === 'header' ? condition.headerName ?? '' : undefined })
  }

  return (
    <div className="condition-row">
      <label className="field">
        <span>Alan</span>
        <select value={condition.field} onChange={(e) => setField(e.target.value as RuleField)}>
          {(Object.entries(RULE_FIELD_LABELS) as [RuleField, string][]).map(([k, label]) => (
            <option key={k} value={k}>{label}</option>
          ))}
        </select>
      </label>

      {condition.field === 'header' && (
        <label className="field">
          <span>Header adı</span>
          <input
            type="text"
            placeholder="User-Agent"
            value={condition.headerName ?? ''}
            onChange={(e) => onChange({ ...condition, headerName: e.target.value })}
          />
        </label>
      )}

      <label className="field">
        <span>Operatör</span>
        <select
          value={condition.operator}
          onChange={(e) => onChange({ ...condition, operator: e.target.value as RuleOperator })}
        >
          {operators.map((op) => (
            <option key={op} value={op}>{OPERATOR_LABELS[op]}</option>
          ))}
        </select>
      </label>

      {needsValue && (
        <label className="field condition-value">
          <span>{isList ? 'Değerler (virgülle)' : 'Değer'}</span>
          <input
            type="text"
            placeholder={isList ? 'TR, DE, US' : RULE_FIELD_HINTS[condition.field]}
            value={condition.value}
            onChange={(e) => onChange({ ...condition, value: e.target.value })}
          />
        </label>
      )}

      {canRemove && (
        <button type="button" className="btn btn-danger condition-remove" onClick={onRemove} title="Koşulu kaldır">
          ×
        </button>
      )}
    </div>
  )
}

export { newCondition }
