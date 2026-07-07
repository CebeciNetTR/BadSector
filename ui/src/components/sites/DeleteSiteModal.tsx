interface Props {
  siteName: string
  onConfirm: () => void
  onCancel: () => void
  deleting: boolean
}

export default function DeleteSiteModal({
  siteName,
  onConfirm,
  onCancel,
  deleting,
}: Props) {
  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Siteyi sil?</h3>
        <p style={{ color: 'var(--muted)', marginTop: '0.75rem' }}>
          <strong>{siteName}</strong> sitesi ve ilişkili pipeline/politika kayıtları
          kalıcı olarak silinecek. Bu işlem geri alınamaz.
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
