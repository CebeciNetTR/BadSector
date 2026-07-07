interface Props {
  policyName: string
  onConfirm: () => void
  onCancel: () => void
  deleting: boolean
}

export default function DeletePolicyModal({
  policyName,
  onConfirm,
  onCancel,
  deleting,
}: Props) {
  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Politikayı sil?</h3>
        <p style={{ color: 'var(--muted)', marginTop: '0.75rem' }}>
          <strong>{policyName}</strong> kalıcı olarak silinecek.
        </p>
        <div className="modal-actions">
          <button type="button" className="btn" onClick={onCancel} disabled={deleting}>
            İptal
          </button>
          <button
            type="button"
            className="btn btn-danger"
            onClick={onConfirm}
            disabled={deleting}
          >
            {deleting ? 'Siliniyor…' : 'Evet, sil'}
          </button>
        </div>
      </div>
    </div>
  )
}
