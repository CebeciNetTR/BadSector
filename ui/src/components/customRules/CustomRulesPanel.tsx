import { useMemo, useState } from 'react'
import { RULE_TEMPLATES } from '../../types/customRuleBuilder'
import { newCustomRule, type CustomRule, type CustomRulesConfig } from '../../types/securityModules'
import CustomRuleEditor, { applyTemplate } from './CustomRuleEditor'
import CustomRuleList from './CustomRuleList'
import FieldReference from './FieldReference'

interface Props {
  enabled: boolean
  config: CustomRulesConfig
  onEnabledChange: (v: boolean) => void
  onConfigChange: (c: CustomRulesConfig) => void
}

export default function CustomRulesPanel({ enabled, config, onEnabledChange, onConfigChange }: Props) {
  const [selectedId, setSelectedId] = useState<string | null>(config.rules[0]?.id ?? null)

  const selectedRule = useMemo(
    () => config.rules.find((r) => r.id === selectedId) ?? null,
    [config.rules, selectedId],
  )

  const updateRules = (rules: CustomRule[]) => {
    onConfigChange({ ...config, rules })
    if (selectedId && !rules.some((r) => r.id === selectedId)) {
      setSelectedId(rules[0]?.id ?? null)
    }
  }

  const addBlankRule = () => {
    const rule = newCustomRule({
      match: {
        expr: 'path contains ""',
        _builder: {
          logic: 'and',
          conditions: [{ id: `c-${Date.now()}`, field: 'path', operator: 'contains', value: '' }],
        },
      },
    })
    updateRules([...config.rules, rule])
    setSelectedId(rule.id)
  }

  const addFromTemplate = (templateId: string) => {
    const rule = applyTemplate(templateId)
    if (!rule) return
    updateRules([...config.rules, rule])
    setSelectedId(rule.id)
  }

  return (
    <div className="custom-rules-panel">
      <div className="card form-grid" style={{ marginBottom: '1rem' }}>
        <label className="checkbox-row">
          <input type="checkbox" checked={enabled} onChange={(e) => onEnabledChange(e.target.checked)} />
          Modül etkin
        </label>
        <label className="checkbox-row">
          <input
            type="checkbox"
            checked={config.fail_open}
            onChange={(e) => onConfigChange({ ...config, fail_open: e.target.checked })}
          />
          Fail open (eval hatasında devam et)
        </label>
      </div>

      <div className="custom-rules-toolbar">
        <button type="button" className="btn btn-primary" onClick={addBlankRule}>
          + Yeni kural
        </button>
        <label className="field template-select">
          <span>Şablondan ekle</span>
          <select
            defaultValue=""
            onChange={(e) => {
              if (e.target.value) {
                addFromTemplate(e.target.value)
                e.target.value = ''
              }
            }}
          >
            <option value="">— Şablon seç —</option>
            {RULE_TEMPLATES.map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
        </label>
      </div>

      <div className="split-layout custom-rules-layout">
        <div className="custom-rules-left">
          <CustomRuleList
            rules={config.rules}
            selectedId={selectedId}
            onSelect={setSelectedId}
          />
          <FieldReference />
        </div>
        <div className="custom-rules-right">
          {selectedRule ? (
            <CustomRuleEditor
              rule={selectedRule}
              onChange={(updated) => {
                updateRules(config.rules.map((r) => (r.id === updated.id ? updated : r)))
              }}
              onDelete={() => updateRules(config.rules.filter((r) => r.id !== selectedRule.id))}
            />
          ) : (
            <div className="card">
              <p className="empty-state">Düzenlemek için soldan bir kural seçin veya yeni kural ekleyin.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
