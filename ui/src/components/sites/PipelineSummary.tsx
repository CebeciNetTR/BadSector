import { MODULE_LABELS, type PipelineStage } from '../../types/site'

interface Props {
  stages: PipelineStage[]
}

export default function PipelineSummary({ stages }: Props) {
  const sorted = [...stages].sort((a, b) => a.order - b.order)

  if (sorted.length === 0) {
    return (
      <div className="card">
        <h3>Pipeline</h3>
        <p className="empty-state">Pipeline tanımlı değil.</p>
      </div>
    )
  }

  return (
    <div className="card">
      <h3>Pipeline Özeti</h3>
      <p className="empty-state" style={{ marginBottom: '0.75rem' }}>
        Bu sitede istekler aşağıdaki modüllerden geçer (yukarıdan aşağıya).
      </p>
      <div className="pipeline-flow">
        <div className="pipeline-node request">İstek</div>
        {sorted.map((stage, index) => (
          <div key={stage.id} className="pipeline-segment">
            <div className="pipeline-arrow">↓</div>
            <div className={`pipeline-node ${stage.enabled ? 'active' : 'inactive'}`}>
              <span className="pipeline-order">{index + 1}</span>
              <span className="pipeline-name">
                {MODULE_LABELS[stage.module] ?? stage.module}
              </span>
              <span className={`badge ${stage.enabled ? 'pass' : 'fail'}`}>
                {stage.enabled ? 'Aktif' : 'Pasif'}
              </span>
            </div>
          </div>
        ))}
        <div className="pipeline-segment">
          <div className="pipeline-arrow">↓</div>
          <div className="pipeline-node backend">Backend</div>
        </div>
      </div>
    </div>
  )
}
