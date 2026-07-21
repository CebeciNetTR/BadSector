import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, ApiError } from '../api/client'
import { parseHosts, type Site } from '../types/site'
import CustomRulesPanel from '../components/customRules/CustomRulesPanel'
import { normalizeRulesForSave } from '../lib/customRuleExpr'
import {
  defaultAsnConfig,
  defaultBurstDetectionConfig,
  defaultCookieChallengeConfig,
  defaultCustomRulesConfig,
  defaultGeoipConfig,
  defaultHeaderValidationConfig,
  defaultJsChallengeConfig,
  DEFAULT_CHALLENGE_TEMPLATE,
  type AsnConfig,
  type BurstDetectionConfig,
  type CookieChallengeConfig,
  type CustomRulesConfig,
  type GeoipConfig,
  type GeoipStatus,
  type HeaderValidationConfig,
  type JsChallengeConfig,
} from '../types/securityModules'

type Tab = 'geoip' | 'asn' | 'headers' | 'custom_rules' | 'burst' | 'challenges'

const tabs: { id: Tab; label: string }[] = [
  { id: 'geoip', label: 'GeoIP' },
  { id: 'asn', label: 'ASN' },
  { id: 'headers', label: 'Header Validation' },
  { id: 'custom_rules', label: 'Custom Rules' },
  { id: 'burst', label: 'Burst Detection' },
  { id: 'challenges', label: 'Challenges' },
]

export default function SecurityModules() {
  const [searchParams] = useSearchParams()
  const initialSiteId = searchParams.get('site') ?? ''
  const initialTab = (searchParams.get('tab') as Tab) || 'geoip'

  const [tab, setTab] = useState<Tab>(initialTab)
  const [sites, setSites] = useState<Site[]>([])
  const [siteId, setSiteId] = useState(initialSiteId)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const [geoipEnabled, setGeoipEnabled] = useState(false)
  const [geoip, setGeoip] = useState<GeoipConfig>(defaultGeoipConfig())
  const [geoStatus, setGeoStatus] = useState<GeoipStatus | null>(null)
  const [asnEnabled, setAsnEnabled] = useState(false)
  const [asn, setAsn] = useState<AsnConfig>(defaultAsnConfig())
  const [headerEnabled, setHeaderEnabled] = useState(false)
  const [headers, setHeaders] = useState<HeaderValidationConfig>(defaultHeaderValidationConfig())
  const [burstEnabled, setBurstEnabled] = useState(false)
  const [burst, setBurst] = useState<BurstDetectionConfig>(defaultBurstDetectionConfig())
  const [jsEnabled, setJsEnabled] = useState(false)
  const [js, setJs] = useState<JsChallengeConfig>(defaultJsChallengeConfig())
  const [cookieEnabled, setCookieEnabled] = useState(false)
  const [cookie, setCookie] = useState<CookieChallengeConfig>(defaultCookieChallengeConfig())
  const [customRulesEnabled, setCustomRulesEnabled] = useState(false)
  const [customRules, setCustomRules] = useState<CustomRulesConfig>(defaultCustomRulesConfig())

  const loadSites = useCallback(async () => {
    const list = await api.listSites()
    setSites(list)
    if (list.length > 0) {
      const preferred = initialSiteId && list.some((s) => s.id === initialSiteId) ? initialSiteId : list[0].id
      setSiteId((c) => c || preferred)
    }
  }, [initialSiteId])

  const loadAll = useCallback(async (id: string) => {
    setLoading(true)
    setError(null)
    try {
      const [geoipRes, asnRes, headerRes, customRes, burstRes, jsRes, cookieRes, status] = await Promise.all([
        api.getGeoip(id),
        api.getAsn(id),
        api.getHeaderValidation(id),
        api.getCustomRules(id),
        api.getBurstDetection(id),
        api.getJsChallenge(id),
        api.getCookieChallenge(id),
        api.getGeoipStatus(),
      ])

      setGeoipEnabled(geoipRes.enabled)
      setGeoip({ ...defaultGeoipConfig(), ...geoipRes.config })
      setGeoStatus(status)
      setAsnEnabled(asnRes.enabled)
      setAsn({ ...defaultAsnConfig(), ...asnRes.config })
      setHeaderEnabled(headerRes.enabled)
      setHeaders({ ...defaultHeaderValidationConfig(), ...headerRes.config })
      setCustomRulesEnabled(customRes.enabled)
      setCustomRules({
        ...defaultCustomRulesConfig(),
        ...customRes.config,
        rules: normalizeRulesForSave(customRes.config.rules ?? []),
      })
      setBurstEnabled(burstRes.enabled)
      setBurst({ ...defaultBurstDetectionConfig(), ...burstRes.config })
      setJsEnabled(jsRes.enabled)
      setJs({ ...defaultJsChallengeConfig(), ...jsRes.config })
      setCookieEnabled(cookieRes.enabled)
      setCookie({ ...defaultCookieChallengeConfig(), ...cookieRes.config })
      setDirty(false)    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Ayarlar yüklenemedi')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadSites().catch((e) => setError(e.message))
  }, [loadSites])

  useEffect(() => {
    if (siteId) loadAll(siteId)
  }, [siteId, loadAll])

  async function save() {
    if (!siteId) return
    setSaving(true)
    setError(null)
    setSuccess(null)
    try {
      if (tab === 'geoip') {
        await api.saveGeoip(siteId, { enabled: geoipEnabled, config: geoip })
      } else if (tab === 'asn') {
        await api.saveAsn(siteId, { enabled: asnEnabled, config: asn })
      } else if (tab === 'headers') {
        await api.saveHeaderValidation(siteId, { enabled: headerEnabled, config: headers })
      } else if (tab === 'custom_rules') {
        const rules = normalizeRulesForSave(customRules.rules)
        await api.saveCustomRules(siteId, {
          enabled: customRulesEnabled,
          config: { ...customRules, enabled: customRulesEnabled, rules },
        })
      } else if (tab === 'burst') {
        await api.saveBurstDetection(siteId, { enabled: burstEnabled, config: burst })
      } else {
        await Promise.all([
          api.saveJsChallenge(siteId, { enabled: jsEnabled, config: js }),
          api.saveCookieChallenge(siteId, { enabled: cookieEnabled, config: cookie }),
        ])
      }
      setDirty(false)
      setSuccess('Kaydedildi ve engine reload tetiklendi.')
      await loadAll(siteId)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Kaydetme başarısız')
    } finally {
      setSaving(false)
    }
  }

  const markDirty = () => setDirty(true)

  return (
    <>
      <div className="page-header">
        <div>
          <h2>Edge Security Modülleri</h2>
          <p className="page-desc">ASN, header doğrulama, burst detection ve challenge modülleri.</p>
        </div>
        <div className="page-actions">
          <button type="button" className="btn-primary" disabled={!dirty || saving} onClick={save}>
            {saving ? 'Kaydediliyor…' : 'Kaydet & Reload'}
          </button>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}
      {success && <p className="form-success">{success}</p>}

      <div className="card">
        <label>
          Site
          <select value={siteId} onChange={(e) => setSiteId(e.target.value)}>
            {sites.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} ({parseHosts(s.hosts).join(', ')})
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="tab-bar">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            className={`tab-btn ${tab === t.id ? 'active' : ''}`}
            onClick={() => setTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="empty-state">Yükleniyor…</p>
      ) : (
        <>
          {tab === 'geoip' && (
            <>
              {geoStatus && (
                <div className="card">
                  <h3>MaxMind Durumu</h3>
                  <div className="edge-status" style={{ marginTop: '0.5rem' }}>
                    <span className={`status-pill ${geoStatus.country_ok ? 'ok' : 'down'}`}>
                      Country MMDB {geoStatus.country_ok ? 'OK' : 'eksik'}
                    </span>
                    <span className={`status-pill ${geoStatus.asn_ok ? 'ok' : 'down'}`}>
                      ASN MMDB {geoStatus.asn_ok ? 'OK' : 'eksik'}
                    </span>
                  </div>
                  {geoStatus.last_sync && (
                    <p className="empty-state">Son sync: {geoStatus.last_sync}</p>
                  )}
                  {!geoStatus.country_ok && (
                    <p className="empty-state">
                      <code>MAXMIND_LICENSE_KEY</code> ayarlayın; worker otomatik indirir. Bkz. docs/GEOIP.md
                    </p>
                  )}
                </div>
              )}
              <div className="card form-grid">
                <label className="checkbox-row">
                  <input type="checkbox" checked={geoipEnabled} onChange={(e) => { setGeoipEnabled(e.target.checked); markDirty() }} />
                  Modül etkin
                </label>
                <label className="checkbox-row">
                  <input type="checkbox" checked={geoip.allow_only} onChange={(e) => { setGeoip({ ...geoip, allow_only: e.target.checked }); markDirty() }} />
                  Yalnızca allow list (allow_countries)
                </label>
                <label className="checkbox-row">
                  <input type="checkbox" checked={geoip.use_header_fallback} onChange={(e) => { setGeoip({ ...geoip, use_header_fallback: e.target.checked }); markDirty() }} />
                  Header fallback (CF-IPCountry)
                </label>
                <label>
                  Reddetme eylemi (allow-list dışı / block list)
                  <select
                    value={geoip.deny_action || 'block'}
                    onChange={(e) => {
                      setGeoip({
                        ...geoip,
                        deny_action: e.target.value as 'block' | 'drop' | 'challenge',
                      })
                      markDirty()
                    }}
                  >
                    <option value="block">403 Block</option>
                    <option value="drop">444 Silent drop</option>
                    <option value="challenge">JS Challenge (PoW)</option>
                  </select>
                </label>
                {(geoip.deny_action || 'block') === 'challenge' && (
                  <>
                    <label>
                      Challenge ban eşiği (60 sn / belge)
                      <input
                        type="number"
                        min={2}
                        max={50}
                        value={geoip.ban_threshold ?? 5}
                        onChange={(e) => {
                          setGeoip({ ...geoip, ban_threshold: Number(e.target.value) })
                          markDirty()
                        }}
                      />
                    </label>
                    <label>
                      Ban süresi (sn)
                      <input
                        type="number"
                        min={60}
                        value={geoip.ban_ttl ?? 86400}
                        onChange={(e) => {
                          setGeoip({ ...geoip, ban_ttl: Number(e.target.value) })
                          markDirty()
                        }}
                      />
                    </label>
                    <p style={{ color: 'var(--muted)', fontSize: '0.8rem', gridColumn: '1 / -1', margin: 0 }}>
                      TR (allow) kullanıcı challenge görmez. Yabancı / block-list: PoW; 60 sn içinde eşik kadar
                      çözümsüz belge isteği → Redis ban (<code>geoip_challenge</code>). Favicon/statik sayılmaz.
                    </p>
                  </>
                )}
                <label>
                  Engellenen ülkeler (ISO, virgülle)
                  <input
                    value={geoip.block_countries.join(', ')}
                    onChange={(e) => {
                      setGeoip({
                        ...geoip,
                        block_countries: e.target.value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean),
                      })
                      markDirty()
                    }}
                  />
                </label>
                <label>
                  İzin verilen ülkeler (ISO, virgülle)
                  <input
                    value={geoip.allow_countries.join(', ')}
                    onChange={(e) => {
                      setGeoip({
                        ...geoip,
                        allow_countries: e.target.value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean),
                      })
                      markDirty()
                    }}
                  />
                </label>
                <hr style={{ gridColumn: '1 / -1', border: 'none', borderTop: '1px solid var(--border)', margin: '0.5rem 0' }} />
                <p style={{ gridColumn: '1 / -1', margin: 0, fontWeight: 600 }}>Attack mode (Dashboard anahtarı)</p>
                <label>
                  Attack mode kernel block (ülke ISO, virgülle)
                  <input
                    placeholder="CN, BR"
                    value={(geoip.attack_block_countries ?? []).join(', ')}
                    onChange={(e) => {
                      setGeoip({
                        ...geoip,
                        attack_block_countries: e.target.value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean),
                      })
                      markDirty()
                    }}
                  />
                </label>
                <p style={{ color: 'var(--muted)', fontSize: '0.8rem', gridColumn: '1 / -1', margin: 0 }}>
                  Attack mode açıkken yalnızca bu ülkeler (ve üstteki <code>Engellenen ülkeler</code> listesi)
                  kernel <code>ipset</code> ile TLS/HAProxy öncesi DROP olur. <code>allow_only</code> attack modunda
                  kernel&apos;e yansımaz — normal mod challenge/allow davranışı ayrı kalır.
                </p>
              </div>
            </>
          )}

          {tab === 'asn' && (
            <div className="card">
              <label className="checkbox-row">
                <input type="checkbox" checked={asnEnabled} onChange={(e) => { setAsnEnabled(e.target.checked); markDirty() }} />
                Modül etkin
              </label>
              <label className="checkbox-row">
                <input type="checkbox" checked={asn.allow_only} onChange={(e) => { setAsn({ ...asn, allow_only: e.target.checked }); markDirty() }} />
                Yalnızca allow list (allow_asns)
              </label>
              <label>
                Engellenen ASN (virgülle)
                <input
                  value={asn.block_asns.join(', ')}
                  onChange={(e) => {
                    setAsn({
                      ...asn,
                      block_asns: e.target.value.split(',').map((x) => parseInt(x.trim(), 10)).filter((n) => !Number.isNaN(n)),
                    })
                    markDirty()
                  }}
                />
              </label>
              <label>
                İzin verilen ASN (virgülle)
                <input
                  value={asn.allow_asns.join(', ')}
                  onChange={(e) => {
                    setAsn({
                      ...asn,
                      allow_asns: e.target.value.split(',').map((x) => parseInt(x.trim(), 10)).filter((n) => !Number.isNaN(n)),
                    })
                    markDirty()
                  }}
                />
              </label>
              <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '1rem 0' }} />
              <p style={{ margin: '0 0 0.5rem', fontWeight: 600 }}>Attack mode</p>
              <label>
                Attack mode reddetme eylemi
                <select
                  value={asn.attack_deny_action || 'drop'}
                  onChange={(e) => {
                    setAsn({
                      ...asn,
                      attack_deny_action: e.target.value as 'drop' | 'block',
                    })
                    markDirty()
                  }}
                >
                  <option value="drop">444 Silent drop (önerilen)</option>
                  <option value="block">403 Block</option>
                </select>
              </label>
              <label>
                Attack mode engelli ASN (virgülle)
                <input
                  placeholder="45899, 394474"
                  value={(asn.attack_block_asns ?? []).join(', ')}
                  onChange={(e) => {
                    setAsn({
                      ...asn,
                      attack_block_asns: e.target.value.split(',').map((x) => parseInt(x.trim(), 10)).filter((n) => !Number.isNaN(n)),
                    })
                    markDirty()
                  }}
                />
              </label>
              <p className="empty-state">
                <strong>Kernel:</strong> Attack modunda listedeki ASN&apos;lere ait IP&apos;ler (hit≥1) watcher ile{' '}
                <code>ipset bs_banned</code>&apos;a yazılır — TLS öncesi DROP. Pipeline&apos;da modül etkin olmalı.
              </p>
              <p className="empty-state">
                ASN lookup: <code>GeoLite2-ASN.mmdb</code> (worker indirir). Manuel override: <code>ip_map</code>.
              </p>
            </div>
          )}

          {tab === 'headers' && (
            <div className="card form-grid">
              <label className="checkbox-row">
                <input type="checkbox" checked={headerEnabled} onChange={(e) => { setHeaderEnabled(e.target.checked); markDirty() }} />
                Modül etkin
              </label>
              <label>
                Zorunlu header&apos;lar (satır başına)
                <textarea
                  rows={3}
                  value={headers.required.join('\n')}
                  onChange={(e) => { setHeaders({ ...headers, required: e.target.value.split('\n').map((x) => x.trim()).filter(Boolean) }); markDirty() }}
                />
              </label>
              <label>
                Yasak header&apos;lar (satır başına)
                <textarea
                  rows={3}
                  value={headers.forbidden.join('\n')}
                  onChange={(e) => { setHeaders({ ...headers, forbidden: e.target.value.split('\n').map((x) => x.trim()).filter(Boolean) }); markDirty() }}
                />
              </label>
            </div>
          )}

          {tab === 'custom_rules' && (
            <CustomRulesPanel
              enabled={customRulesEnabled}
              config={customRules}
              onEnabledChange={(v) => { setCustomRulesEnabled(v); markDirty() }}
              onConfigChange={(c) => { setCustomRules(c); markDirty() }}
            />
          )}

          {tab === 'burst' && (
            <div className="card form-grid">
              <label className="checkbox-row">
                <input type="checkbox" checked={burstEnabled} onChange={(e) => { setBurstEnabled(e.target.checked); markDirty() }} />
                Modül etkin
              </label>
              <label>
                Pencere (sn)
                <input type="number" value={burst.window} onChange={(e) => { setBurst({ ...burst, window: Number(e.target.value) }); markDirty() }} />
              </label>
              <label>
                Eşik
                <input type="number" value={burst.threshold} onChange={(e) => { setBurst({ ...burst, threshold: Number(e.target.value) }); markDirty() }} />
              </label>
              <label>
                Key
                <select value={burst.key_by} onChange={(e) => { setBurst({ ...burst, key_by: e.target.value as BurstDetectionConfig['key_by'] }); markDirty() }}>
                  <option value="ip">IP</option>
                  <option value="ip_path">IP + Path</option>
                  <option value="global">Global</option>
                </select>
              </label>
              <label>
                Aksiyon
                <select value={burst.action} onChange={(e) => { setBurst({ ...burst, action: e.target.value as BurstDetectionConfig['action'] }); markDirty() }}>
                  <option value="rate_limit">Rate Limit (429)</option>
                  <option value="block">Block</option>
                </select>
              </label>
              <label>
                Path patterns (satır başına)
                <textarea
                  rows={3}
                  value={burst.paths.join('\n')}
                  onChange={(e) => { setBurst({ ...burst, paths: e.target.value.split('\n').map((x) => x.trim()).filter(Boolean) }); markDirty() }}
                />
              </label>
            </div>
          )}

          {tab === 'challenges' && (
            <>
              <div className="card form-grid">
                <h3>JS Challenge (imzalı Proof-of-Work)</h3>
                <p style={{ color: 'var(--muted)', fontSize: '0.85rem', margin: 0 }}>
                  Stateless HMAC + JS PoW. Zorluk attack mode'da otomatik yükselir.
                  Çözen istemciye imzalı <code>bs_pass</code> geçiş cookie'si verilir.
                </p>
                <label className="checkbox-row">
                  <input type="checkbox" checked={jsEnabled} onChange={(e) => { setJsEnabled(e.target.checked); markDirty() }} />
                  Etkin
                </label>
                <label>
                  Zorluk (normal) — baştaki hex sıfır sayısı
                  <input type="number" min={1} max={8} value={js.difficulty} onChange={(e) => { setJs({ ...js, difficulty: Number(e.target.value) }); markDirty() }} />
                </label>
                <label>
                  Zorluk (attack mode)
                  <input type="number" min={1} max={10} value={js.difficulty_attack} onChange={(e) => { setJs({ ...js, difficulty_attack: Number(e.target.value) }); markDirty() }} />
                </label>
                <label>
                  Pass süresi (sn)
                  <input type="number" value={js.pass_ttl} onChange={(e) => { setJs({ ...js, pass_ttl: Number(e.target.value) }); markDirty() }} />
                </label>
                <label>
                  Path patterns
                  <textarea rows={2} value={js.paths.join('\n')} onChange={(e) => { setJs({ ...js, paths: e.target.value.split('\n').filter(Boolean) }); markDirty() }} />
                </label>
                <label>
                  Hariç tutulan path
                  <textarea rows={2} value={js.exclude_paths.join('\n')} onChange={(e) => { setJs({ ...js, exclude_paths: e.target.value.split('\n').filter(Boolean) }); markDirty() }} />
                </label>

                <div style={{ borderTop: '1px solid var(--border)', paddingTop: '1rem', marginTop: '0.5rem' }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '0.5rem' }}>
                    <strong style={{ fontSize: '0.95rem' }}>Challenge sayfası (özel HTML/CSS)</strong>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                      <button
                        type="button"
                        className="btn btn-sm"
                        onClick={() => { setJs({ ...js, template: DEFAULT_CHALLENGE_TEMPLATE }); markDirty() }}
                      >
                        Varsayılanı yükle
                      </button>
                      <button
                        type="button"
                        className="btn btn-sm"
                        onClick={() => { setJs({ ...js, template: '' }); markDirty() }}
                        disabled={!js.template}
                      >
                        Sıfırla
                      </button>
                    </div>
                  </div>
                  <p style={{ color: 'var(--muted)', fontSize: '0.8rem', margin: '0.5rem 0 0.75rem' }}>
                    Boş bırakırsan önce sunucudaki global dosya
                    {' '}<code>data/challenge/template.html</code> (git&apos;te yok), yoksa yerleşik sayfa kullanılır.
                    PoW çözücü <code>&lt;script&gt;</code> her zaman otomatik eklenir;
                    HTML&apos;inde <code>&lt;/body&gt;</code> varsa hemen öncesine enjekte edilir.
                    İstersen <code>{'{{difficulty}}'}</code> yer tutucusunu kullanabilirsin.
                  </p>
                  <textarea
                    rows={14}
                    spellCheck={false}
                    style={{ fontFamily: 'monospace', fontSize: '0.8rem', whiteSpace: 'pre', overflowWrap: 'normal', overflowX: 'auto' }}
                    placeholder="Boş = varsayılan sayfa. Kendi HTML/CSS'ini buraya yaz."
                    value={js.template ?? ''}
                    onChange={(e) => { setJs({ ...js, template: e.target.value }); markDirty() }}
                  />
                </div>
              </div>
              <div className="card form-grid">
                <h3>Cookie Challenge</h3>
                <label className="checkbox-row">
                  <input type="checkbox" checked={cookieEnabled} onChange={(e) => { setCookieEnabled(e.target.checked); markDirty() }} />
                  Etkin
                </label>
                <label>
                  Cookie adı
                  <input value={cookie.cookie_name} onChange={(e) => { setCookie({ ...cookie, cookie_name: e.target.value }); markDirty() }} />
                </label>
                <label>
                  TTL (sn)
                  <input type="number" value={cookie.cookie_ttl} onChange={(e) => { setCookie({ ...cookie, cookie_ttl: Number(e.target.value) }); markDirty() }} />
                </label>
              </div>
            </>
          )}
        </>
      )}
    </>
  )
}
