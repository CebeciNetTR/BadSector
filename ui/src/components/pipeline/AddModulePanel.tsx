import { moduleLabel } from '../../types/pipeline'

interface Props {
  available: string[]
  onAdd: (module: string) => void
}

export default function AddModulePanel({ available, onAdd }: Props) {
  if (available.length === 0) {
    return (
      <div className="card">
        <h3>Modül Ekle</h3>
        <p className="empty-state">Tüm modüller pipeline&apos;a eklenmiş.</p>
      </div>
    )
  }

  return (
    <div className="card">
      <h3>Modül Ekle</h3>
      <p className="empty-state" style={{ marginBottom: '0.75rem' }}>
        Pipeline&apos;a yeni bir modül ekleyin. Sıralamayı sürükleyerek değiştirin.
      </p>
      <div className="module-grid">
        {available.map((module) => (
          <button
            key={module}
            type="button"
            className="module-add-btn"
            onClick={() => onAdd(module)}
          >
            <span className="module-add-name">{moduleLabel(module)}</span>
            <span className="muted-inline mono">{module}</span>
          </button>
        ))}
      </div>
    </div>
  )
}
