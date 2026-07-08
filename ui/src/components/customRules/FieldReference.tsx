import {
  RULE_FIELD_HINTS,
  RULE_FIELD_LABELS,
  RULE_TEMPLATES,
} from '../../types/customRuleBuilder'

export default function FieldReference() {
  return (
    <div className="card field-reference">
      <h3>Kullanılabilir alanlar</h3>
      <p className="empty-state">
        Görsel oluşturucuda seçebileceğiniz alanlar. Engine güvenli ifade dilini kullanır; ham Lua çalıştırılmaz.
      </p>
      <table className="ref-table">
        <thead>
          <tr>
            <th>Alan</th>
            <th>Örnek</th>
          </tr>
        </thead>
        <tbody>
          {(Object.entries(RULE_FIELD_LABELS) as [keyof typeof RULE_FIELD_LABELS, string][]).map(([key, label]) => (
            <tr key={key}>
              <td><code>{key}</code><br /><span className="muted-inline">{label}</span></td>
              <td className="muted-inline">{RULE_FIELD_HINTS[key]}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h4 style={{ marginTop: '1.25rem' }}>Hazır şablonlar</h4>
      <ul className="template-list">
        {RULE_TEMPLATES.map((t) => (
          <li key={t.id}>
            <strong>{t.name}</strong>
            <p className="muted-inline">{t.description}</p>
          </li>
        ))}
      </ul>

      <h4 style={{ marginTop: '1rem' }}>Pipeline notu</h4>
      <p className="empty-state">
        <code>trusted_bot</code> için <code>trusted_bots</code> modülü kuraldan <strong>önce</strong> çalışmalıdır.
        <code>country</code> / <code>asn</code> için GeoIP modülü etkin olmalıdır.
      </p>
    </div>
  )
}
