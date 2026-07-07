import { Link } from 'react-router-dom'
import { parseHosts, type Site } from '../../types/site'

interface Props {
  sites: Site[]
  selectedId: string | null
  onSelect: (id: string) => void
  onAdd: () => void
  onDelete: (site: Site) => void
}

export default function SiteList({
  sites,
  selectedId,
  onSelect,
  onAdd,
  onDelete,
}: Props) {
  return (
    <div className="card">
      <div className="card-header">
        <h3>Siteler</h3>
        <button type="button" className="btn btn-primary" onClick={onAdd}>
          + Site ekle
        </button>
      </div>

      {sites.length === 0 ? (
        <p className="empty-state">Henüz site yok. İlk sitenizi oluşturun.</p>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Durum</th>
                <th>Ad</th>
                <th>Hostnames</th>
                <th>Güncelleme</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {sites.map((site) => {
                const hosts = parseHosts(site.hosts)
                return (
                  <tr
                    key={site.id}
                    className={selectedId === site.id ? 'selected' : ''}
                    onClick={() => onSelect(site.id)}
                  >
                    <td>
                      <span className={`badge ${site.enabled ? 'pass' : 'fail'}`}>
                        {site.enabled ? 'Aktif' : 'Pasif'}
                      </span>
                    </td>
                    <td>
                      <strong>{site.name}</strong>
                      <div className="muted-inline mono">{site.id.slice(0, 8)}…</div>
                    </td>
                    <td>
                      <span className="mono">{hosts.join(', ') || '—'}</span>
                    </td>
                    <td className="muted-inline">
                      {site.updated_at
                        ? new Date(site.updated_at).toLocaleString('tr-TR')
                        : '—'}
                    </td>
                    <td className="actions-cell" onClick={(e) => e.stopPropagation()}>
                      <Link
                        to={`/managed-waf?site=${site.id}`}
                        className="btn btn-sm"
                        title="Managed WAF"
                      >
                        WAF
                      </Link>
                      <Link
                        to={`/pipeline?site=${site.id}`}
                        className="btn btn-sm"
                        title="Pipeline düzenle"
                      >
                        Pipeline
                      </Link>
                      <Link
                        to={`/policies?site=${site.id}`}
                        className="btn btn-sm"
                        title="Politikalar"
                      >
                        Politikalar
                      </Link>
                      <Link
                        to={`/rate-limits?site=${site.id}`}
                        className="btn btn-sm"
                        title="Rate limit ayarları"
                      >
                        Rate Limit
                      </Link>
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        onClick={() => onDelete(site)}
                      >
                        Sil
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
