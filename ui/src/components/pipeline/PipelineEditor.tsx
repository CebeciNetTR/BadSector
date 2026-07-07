import { useState } from 'react'
import {
  LOCKED_LAST_MODULE,
  moduleLabel,
  moveStage,
  removeStage,
  splitPipeline,
  toggleStage,
  type EditablePipelineStage,
} from '../../types/pipeline'

interface Props {
  stages: EditablePipelineStage[]
  onChange: (stages: EditablePipelineStage[]) => void
}

export default function PipelineEditor({ stages, onChange }: Props) {
  const [dragIndex, setDragIndex] = useState<number | null>(null)
  const [overIndex, setOverIndex] = useState<number | null>(null)

  const { draggable, proxy } = splitPipeline(stages)

  const handleDragStart = (index: number) => {
    setDragIndex(index)
  }

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault()
    setOverIndex(index)
  }

  const handleDrop = (index: number) => {
    if (dragIndex === null || dragIndex === index) {
      setDragIndex(null)
      setOverIndex(null)
      return
    }
    onChange(moveStage(stages, dragIndex, index))
    setDragIndex(null)
    setOverIndex(null)
  }

  const handleDragEnd = () => {
    setDragIndex(null)
    setOverIndex(null)
  }

  return (
    <div className="pipeline-editor">
      <div className="pipeline-node request">İstek</div>

      {draggable.map((stage, index) => (
        <div key={stage.key} className="dnd-segment">
          <div className="pipeline-arrow">↓</div>
          <div
            className={`dnd-item ${stage.enabled ? 'active' : 'inactive'} ${
              dragIndex === index ? 'dragging' : ''
            } ${overIndex === index && dragIndex !== index ? 'drag-over' : ''}`}
            draggable
            onDragStart={() => handleDragStart(index)}
            onDragOver={(e) => handleDragOver(e, index)}
            onDrop={() => handleDrop(index)}
            onDragEnd={handleDragEnd}
          >
            <span className="dnd-handle" title="Sürükleyerek sırala">⠿</span>
            <span className="pipeline-order">{index + 1}</span>
            <div className="dnd-info">
              <strong>{moduleLabel(stage.module)}</strong>
              <span className="muted-inline mono">{stage.module}</span>
            </div>
            <label
              className="toggle compact"
              onClick={(e) => e.stopPropagation()}
              onMouseDown={(e) => e.stopPropagation()}
            >
              <input
                type="checkbox"
                checked={stage.enabled}
                onChange={(e) => onChange(toggleStage(stages, stage.key, e.target.checked))}
              />
            </label>
            <span className={`badge ${stage.enabled ? 'pass' : 'fail'}`}>
              {stage.enabled ? 'Aktif' : 'Pasif'}
            </span>
            <button
              type="button"
              className="btn btn-sm"
              title="Modülü kaldır"
              onMouseDown={(e) => e.stopPropagation()}
              onClick={() => onChange(removeStage(stages, stage.key))}
            >
              ✕
            </button>
          </div>
        </div>
      ))}

      {proxy && (
        <div className="dnd-segment">
          <div className="pipeline-arrow">↓</div>
          <div className={`dnd-item locked ${proxy.enabled ? 'active' : 'inactive'}`}>
            <span className="dnd-handle locked" title="Sabit — son modül">🔒</span>
            <span className="pipeline-order">{draggable.length + 1}</span>
            <div className="dnd-info">
              <strong>{moduleLabel(proxy.module)}</strong>
              <span className="muted-inline">Her zaman sonda</span>
            </div>
            <label
              className="toggle compact"
              onClick={(e) => e.stopPropagation()}
            >
              <input
                type="checkbox"
                checked={proxy.enabled}
                onChange={(e) => onChange(toggleStage(stages, proxy.key, e.target.checked))}
              />
            </label>
            <span className={`badge ${proxy.enabled ? 'pass' : 'fail'}`}>
              {proxy.enabled ? 'Aktif' : 'Pasif'}
            </span>
          </div>
        </div>
      )}

      <div className="dnd-segment">
        <div className="pipeline-arrow">↓</div>
        <div className="pipeline-node backend">Backend</div>
      </div>

      {!proxy && (
        <p className="empty-state" style={{ marginTop: '0.75rem' }}>
          Uyarı: {moduleLabel(LOCKED_LAST_MODULE)} modülü eksik. Kaydetmeden önce ekleyin.
        </p>
      )}
    </div>
  )
}
