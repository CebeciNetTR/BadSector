--[[
  BadSector Trusted Bot Verification

  Amac: Googlebot/Bingbot/YandexBot gibi arama motoru botlarini UCUZ ama SAGLAM
  dogrulamak. Dogrulanan bot tum korumalardan muaf tutulacagi icin (WAF dahil),
  sahte UA'li saldirganin gecmemesi kritik.

  Katmanli dogrulama:
    1) UA eslesmesi yoksa      -> bot degil (DNS'e hic gidilmez).
    2) IP resmi prefix'te ise  -> hizli yol, DOGRU (DNS yok).
    3) Aksi halde              -> rDNS: PTR ile hostname bul, beklenen domain
                                  suffix'i tut, sonra forward A kaydiyla IP'yi
                                  teyit et (forward-confirmed reverse DNS).
  Sonuc IP basina paylasimli bellekte cache'lenir (pozitif uzun, negatif kisa TTL)
  boylece istek basina DNS maliyeti amorti edilir ve DNS amplifikasyonu onlenir.
]]

local attack_mode = require("badsector.attack_mode")

local _M = {}

local POS_TTL = tonumber(os.getenv("BADSECTOR_BOT_VERIFY_TTL")) or 86400      -- 24h
local NEG_TTL = tonumber(os.getenv("BADSECTOR_BOT_VERIFY_NEG_TTL")) or 3600   -- 1h
local DNS_TIMEOUT = tonumber(os.getenv("BADSECTOR_DNS_TIMEOUT")) or 2000      -- ms

-- Bilinen botlar: UA alt dizesi, resmi IP prefix'leri (hizli yol) ve rDNS
-- hostname suffix'leri (rDNS dogrulamasi icin). DuckDuckBot rDNS yayinlamaz,
-- yalnizca prefix ile dogrulanir (rdns yok).
local KNOWN_BOTS = {
    { name = "Googlebot",   ua = "Googlebot",   prefixes = { "66.249." },
      rdns = { ".googlebot.com", ".google.com" } },
    { name = "Bingbot",     ua = "bingbot",     prefixes = { "157.55.", "207.46.", "40.77.", "13.66.", "13.67." },
      rdns = { ".search.msn.com" } },
    { name = "YandexBot",   ua = "YandexBot",   prefixes = { "5.255.", "87.250.", "95.108.", "100.43.", "141.8." },
      rdns = { ".yandex.com", ".yandex.net", ".yandex.ru" } },
    { name = "DuckDuckBot", ua = "DuckDuckBot", prefixes = { "40.88.", "52.149.", "54.208." },
      rdns = {} },
}

local function dict()
    return ngx.shared.badsector_counters
end

local function resolvers()
    local raw = os.getenv("BADSECTOR_DNS_RESOLVER") or "127.0.0.11"
    local out = {}
    for host in raw:gmatch("[^,%s]+") do
        out[#out + 1] = host
    end
    if #out == 0 then
        out = { "127.0.0.11" }
    end
    return out
end

local function ip_prefix_match(ip, prefixes)
    if not ip or not prefixes then
        return false
    end
    for _, prefix in ipairs(prefixes) do
        if ip:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function match_ua(ua)
    ua = ua or ""
    if ua == "" then
        return nil
    end
    for _, bot in ipairs(KNOWN_BOTS) do
        if ua:find(bot.ua, 1, true) then
            return bot
        end
    end
    return nil
end

--- IPv4 -> in-addr.arpa (rDNS icin). IPv6/gecersiz icin nil.
local function arpa_name(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return nil
    end
    return d .. "." .. c .. "." .. b .. "." .. a .. ".in-addr.arpa"
end

local function suffix_match(host, suffixes)
    if not host or #suffixes == 0 then
        return false
    end
    host = host:lower()
    -- Sondaki noktayi at (FQDN "host.googlebot.com." -> "host.googlebot.com")
    host = host:gsub("%.$", "")
    for _, suf in ipairs(suffixes) do
        if #host >= #suf and host:sub(-#suf) == suf then
            return true
        end
    end
    return false
end

--- Forward-confirmed reverse DNS.
---@return boolean
local function rdns_verify(ip, suffixes)
    if #suffixes == 0 then
        return false
    end
    local arpa = arpa_name(ip)
    if not arpa then
        return false  -- IPv6 vb. rDNS yolu desteklenmiyor -> prefix'e guveniriz
    end

    local ok, resolver = pcall(require, "resty.dns.resolver")
    if not ok then
        ngx.log(ngx.WARN, "badsector bot_verify: resty.dns.resolver yok")
        return false
    end

    local r, err = resolver:new({
        nameservers = resolvers(),
        retrans = 2,
        timeout = DNS_TIMEOUT,
    })
    if not r then
        ngx.log(ngx.WARN, "badsector bot_verify: resolver init hata: ", err or "?")
        return false
    end

    -- 1) PTR: IP -> hostname
    local ans, qerr = r:query(arpa, { qtype = r.TYPE_PTR }, {})
    if not ans or ans.errcode then
        return false
    end
    local hostname
    for _, rec in ipairs(ans) do
        if rec.ptrdname then
            hostname = rec.ptrdname
            break
        end
    end
    if not hostname or not suffix_match(hostname, suffixes) then
        return false
    end

    -- 2) Forward-confirm: hostname -> A kaydi, orijinal IP ile eslesmeli
    local fwd, ferr = r:query(hostname, { qtype = r.TYPE_A }, {})
    if not fwd or fwd.errcode then
        return false
    end
    for _, rec in ipairs(fwd) do
        if rec.address == ip then
            return true
        end
    end
    return false
end

--- Bot dogrulama (cache'li).
---@param ip string
---@param ua string
---@return string|nil name  Dogrulanmis bot adi (yoksa nil)
---@return boolean verified
function _M.verify(ip, ua)
    local bot = match_ua(ua)
    if not bot then
        return nil, false  -- bot UA'si yok -> DNS'e gidilmez
    end

    if not ip or ip == "" then
        return bot.name, false
    end

    local d = dict()
    local cache_key = "botverify:" .. ip
    if d then
        local cached = d:get(cache_key)
        if cached ~= nil then
            if cached == "0" then
                return bot.name, false
            end
            -- cache'te bot adi tutuluyor
            return cached, true
        end
    end

    local verified = false

    -- Hizli yol: resmi prefix eslesmesi (DNS yok)
    if ip_prefix_match(ip, bot.prefixes) then
        verified = true
    elseif attack_mode.is_on() then
        -- Saldiri aninda pahali rDNS yapma: sahte "Googlebot" UA'li binlerce IP
        -- bizi DNS sorgusuna bogabilir. Sadece prefix'e guven. Prefix disi
        -- (dogrulanmamis) bot bu sure boyunca normal korumalardan gecer.
        -- Negatif sonucu KISA cache'le ki saldiri bitince rDNS tekrar denensin.
        if d then
            d:set(cache_key, "0", 60)
        end
        return bot.name, false
    else
        -- Yavas yol: forward-confirmed rDNS (yalnizca bot UA'li + prefix disi trafik)
        verified = rdns_verify(ip, bot.rdns)
    end

    if d then
        if verified then
            d:set(cache_key, bot.name, POS_TTL)
        else
            d:set(cache_key, "0", NEG_TTL)
        end
    end

    return bot.name, verified
end

return _M
