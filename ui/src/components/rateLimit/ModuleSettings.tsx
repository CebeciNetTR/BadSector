import type { RateLimitConfig } from '../../types/rateLimit'

interface Props {
  enabled: boolean
  config: RateLimitConfig
  onEnabledChange: (enabled: boolean) => void
  onConfigChange: (config: RateLimitConfig) => void
}

export default function ModuleSettings({
  enabled,
  config,
  onEnabledChange,
  onConfigChange,
}: Props) {
  const update = (patch: Partial<RateLimitConfig>) => {
    onConfigChange({ ...config, ...patch })
  }

  const updateRedis = (patch: Partial<RateLimitConfig['redis']>) => {
    onConfigChange({ ...config, redis: { ...config.redis, ...patch } })
  }

  return (
    <div className="card">
      <div className="card-header">
        <h3>Modül Ayarları</h3>
        <label className="toggle">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => onEnabledChange(e.target.checked)}
          />
          <span>{enabled ? 'Aktif' : 'Pasif'}</span>
        </label>
      </div>

      <div className="form-grid">
        <label className="field">
          <span>Redis kullan</span>
          <select
            value={config.use_redis ? 'yes' : 'no'}
            onChange={(e) => update({ use_redis: e.target.value === 'yes' })}
          >
            <option value="yes">Evet (önerilen)</option>
            <option value="no">Hayır — sadece shared dict</option>
          </select>
        </label>

        <label className="field">
          <span>Hata modu</span>
          <select
            value={config.fail_mode}
            onChange={(e) => update({ fail_mode: e.target.value as RateLimitConfig['fail_mode'] })}
          >
            <option value="open">Açık — backend yoksa izin ver</option>
            <option value="closed">Kapalı — backend yoksa reddet</option>
          </select>
        </label>

        <label className="field">
          <span>Redis host</span>
          <input
            type="text"
            value={config.redis?.host ?? 'redis'}
            onChange={(e) => updateRedis({ host: e.target.value })}
          />
        </label>

        <label className="field">
          <span>Redis port</span>
          <input
            type="number"
            value={config.redis?.port ?? 6379}
            onChange={(e) => updateRedis({ port: Number(e.target.value) })}
          />
        </label>
      </div>
    </div>
  )
}
