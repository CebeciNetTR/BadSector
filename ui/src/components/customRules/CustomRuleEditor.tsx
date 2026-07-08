import { useEffect, useState } from 'react'
import { buildExpr, resolveBuilder, syncMatchFromBuilder } from '../../lib/customRuleExpr'
import {
  RULE_TEMPLATES,
  defaultBuilderState,
  newCondition,
  type CustomRuleBuilderState,
} from '../../types/customRuleBuilder'
import type { CustomRule, CustomRuleActionType } from '../../types/securityModules'
import ConditionRow from './ConditionRow'

type EditMode = 'visual' | 'expr' | 'json'

interface Props {
  rule: CustomRule
  onChange: (rule: CustomRule) => void
  onDelete: () => void
}

export default function CustomRuleEditor({ rule, onChange, onDelete }: Props) {
  const [mode, setMode] = useState<EditMode>('visual')
  const [builder, setBuilder] = useState<CustomRuleBuilderState>(() => resolveBuilder(rule.match))
  const [exprDraft, setExprDraft] = useState(rule.match.expr ?? '')
  const [jsonDraft, setJsonDraft] = useState('')
  const [jsonError, setJsonError] = useState<string | null>(null)

  useEffect(() => {
    setBuilder(resolveBuilder(rule.match))
    setExprDraft(rule.match.expr ?? '')
  }, [rule.id])

  const previewExpr = mode === 'visual' ? buildExpr(builder) : exprDraft

  const applyBuilder = (next: CustomRuleBuilderState) => {
    setBuilder(next)
    const match = syncMatchFromBuilder(next, rule.match)
    onChange({ ...rule, match })
    setExprDraft(match.expr ?? '')
  }

  const applyExpr = (expr: string) => {
    setExprDraft(expr)
    onChange({
      ...rule,
      match: { ...rule.match, expr, _builder: undefined },
    })
  }

  const applyFromJson = () => {
    try {
      const parsed = JSON.parse(jsonDraft) as CustomRule
      setJsonError(null)
      onChange(parsed)
      setBuilder(resolveBuilder(parsed.match))
      setExprDraft(parsed.match.expr ?? '')
    } catch (e) {
      setJsonError(e instanceof Error ? e.message : 'Geçersiz JSON')
    }
  }

  const updateAction = (patch: Partial<CustomRule['action']>) => {
    onChange({ ...rule, action: { ...rule.action, ...patch } })
  }

  return (
    <div className="card custom-rule-editor">
      <div className="card-header">
        <h3>Kural düzenle</h3>
        <label className="checkbox-row">
          <input
            type="checkbox"
            checked={rule.enabled !== false}
            onChange={(e) => onChange({ ...rule, enabled: e.target.checked })}
          />
          Etkin
        </label>
      </div>

      <div className="form-grid">
        <label className="field span-2">
          <span>Kural adı</span>
          <input
            type="text"
            value={rule.name}
            onChange={(e) => onChange({ ...rule, name: e.target.value })}
          />
        </label>

        <label className="field">
          <span>Öncelik</span>
          <input
            type="number"
            min={1}
            value={rule.priority ?? 100}
            onChange={(e) => onChange({ ...rule, priority: Number(e.target.value) })}
          />
        </label>

        <label className="field">
          <span>Aksiyon</span>
          <select
            value={rule.action.type}
            onChange={(e) => updateAction({ type: e.target.value as CustomRuleActionType })}
          >
            <option value="block">Engelle (Block)</option>
            <option value="allow">İzin ver (Allow)</option>
            <option value="rate_limit">Rate limit</option>
            <option value="redirect">Yönlendir</option>
            <option value="log">Sadece log</option>
          </select>
        </label>

        {rule.action.type === 'block' && (
          <label className="field">
            <span>HTTP durum</span>
            <select
              value={String(rule.action.status ?? 403)}
              onChange={(e) => updateAction({ status: Number(e.target.value) })}
            >
              <option value="403">403 Forbidden</option>
              <option value="404">404 Not Found</option>
              <option value="429">429 Too Many Requests</option>
              <option value="444">444 (bağlantı kapat)</option>
            </select>
          </label>
        )}

        {rule.action.type === 'redirect' && (
          <label className="field span-2">
            <span>Hedef URL</span>
            <input
              type="text"
              placeholder="https://example.com/blocked"
              value={rule.action.url ?? ''}
              onChange={(e) => updateAction({ url: e.target.value })}
            />
          </label>
        )}
      </div>

      <div className="mode-tabs">
        <button type="button" className={mode === 'visual' ? 'mode-tab active' : 'mode-tab'} onClick={() => setMode('visual')}>
          Görsel oluşturucu
        </button>
        <button
          type="button"
          className={mode === 'expr' ? 'mode-tab active' : 'mode-tab'}
          onClick={() => {
            setExprDraft(rule.match.expr ?? buildExpr(builder))
            setMode('expr')
          }}
        >
          Ham ifade
        </button>
        <button
          type="button"
          className={mode === 'json' ? 'mode-tab active' : 'mode-tab'}
          onClick={() => {
            setJsonDraft(JSON.stringify(rule, null, 2))
            setJsonError(null)
            setMode('json')
          }}
        >
          Ham JSON
        </button>
      </div>

      {mode === 'visual' && (
        <div className="visual-builder">
          <div className="builder-toolbar">
            <label className="field">
              <span>Koşullar birleşimi</span>
              <select
                value={builder.logic}
                onChange={(e) => applyBuilder({ ...builder, logic: e.target.value as 'and' | 'or' })}
              >
                <option value="and">Tümü sağlanmalı (AND)</option>
                <option value="or">Biri yeterli (OR)</option>
              </select>
            </label>
            <button
              type="button"
              className="btn"
              onClick={() => applyBuilder({ ...builder, conditions: [...builder.conditions, newCondition()] })}
            >
              + Koşul ekle
            </button>
          </div>

          {builder.conditions.map((c, idx) => (
            <ConditionRow
              key={c.id}
              condition={c}
              canRemove={builder.conditions.length > 1}
              onChange={(next) => {
                const conditions = [...builder.conditions]
                conditions[idx] = next
                applyBuilder({ ...builder, conditions })
              }}
              onRemove={() => {
                const conditions = builder.conditions.filter((_, i) => i !== idx)
                applyBuilder({ ...builder, conditions: conditions.length ? conditions : [newCondition()] })
              }}
            />
          ))}

          <div className="expr-preview">
            <span className="preview-label">Oluşan ifade</span>
            <code>{previewExpr || '(koşul girin)'}</code>
          </div>
        </div>
      )}

      {mode === 'expr' && (
        <div className="expr-editor">
          <label className="field">
            <span>İfade (expr)</span>
            <textarea
              rows={4}
              value={exprDraft}
              onChange={(e) => setExprDraft(e.target.value)}
              placeholder='path contains "wp-" and trusted_bot != true'
            />
          </label>
          <button type="button" className="btn btn-primary" onClick={() => applyExpr(exprDraft)}>
            İfadeyi uygula
          </button>
          <p className="empty-state" style={{ marginTop: '0.75rem' }}>
            Ham ifade modunda görsel oluşturucu devre dışı kalır. Kaydettiğinizde engine bu metni kullanır.
          </p>
        </div>
      )}

      {mode === 'json' && (
        <div className="json-editor">
          <label className="field">
            <span>Kural JSON (tam config)</span>
            <textarea rows={12} value={jsonDraft} onChange={(e) => setJsonDraft(e.target.value)} spellCheck={false} />
          </label>
          {jsonError && <p className="error-text">{jsonError}</p>}
          <button type="button" className="btn btn-primary" onClick={applyFromJson}>
            JSON uygula
          </button>
        </div>
      )}

      <div className="editor-actions">
        <button type="button" className="btn btn-danger" onClick={onDelete}>
          Kuralı sil
        </button>
      </div>
    </div>
  )
}

export function applyTemplate(templateId: string): CustomRule | null {
  const t = RULE_TEMPLATES.find((x) => x.id === templateId)
  if (!t) return null
  return {
    id: `rule-${Date.now()}`,
    name: t.rule.name,
    enabled: true,
    priority: 100,
    match: { ...t.rule.match },
    action: { ...t.rule.action },
  }
}

export { RULE_TEMPLATES, defaultBuilderState }
