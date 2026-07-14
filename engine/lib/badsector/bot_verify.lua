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
local cjson = require("cjson.safe")

local _M = {}

local POS_TTL = tonumber(os.getenv("BADSECTOR_BOT_VERIFY_TTL")) or 86400      -- 24h
local NEG_TTL = tonumber(os.getenv("BADSECTOR_BOT_VERIFY_NEG_TTL")) or 3600   -- 1h
local DNS_TIMEOUT = tonumber(os.getenv("BADSECTOR_DNS_TIMEOUT")) or 2000      -- ms

-- Worker'in gunluk yazdigi resmi bot IP aralik dosyasi (Googlebot/Bingbot).
-- Statik prefix'lerin aksine bu liste guncel tutulur; engine periyodik yeniden yukler.
local RANGES_FILE = (os.getenv("BADSECTOR_BOTS_PATH") or "/etc/badsector/bots") .. "/bot-ranges.json"
local RANGES_RELOAD = tonumber(os.getenv("BADSECTOR_BOTS_RELOAD_SEC")) or 60   -- s

-- Dinamik aralik durumu (worker basina modul state): name -> { v4 = {...}, v6 = {...} }
local _dyn = nil
local _dyn_checked_at = nil

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

-- ---- Dinamik CIDR eslestirme (IPv4 kesin, IPv6 nibble/4-bit granulariteli) ----

local function ipv4_to_num(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return nil
    end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function parse_v4_cidr(cidr)
    local ip, bits = cidr:match("^([%d%.]+)/(%d+)$")
    if not ip then
        return nil
    end
    bits = tonumber(bits)
    local num = ipv4_to_num(ip)
    if not num or bits < 0 or bits > 32 then
        return nil
    end
    local shift = 2 ^ (32 - bits)
    return { top = math.floor(num / shift), shift = shift }
end

local function v4_match(entry, ipnum)
    return math.floor(ipnum / entry.shift) == entry.top
end

--- IPv6'yi 32 hex karaktere ("::" acilmis, gruplar 0-padli) genisletir.
local function expand_v6(ip)
    ip = ip:lower()
    local groups = {}
    local head, tail = ip:match("^(.-)::(.*)$")
    if head ~= nil then
        local h, t = {}, {}
        for part in head:gmatch("[^:]+") do h[#h + 1] = part end
        for part in tail:gmatch("[^:]+") do t[#t + 1] = part end
        local missing = 8 - (#h + #t)
        if missing < 0 then
            return nil
        end
        for _, g in ipairs(h) do groups[#groups + 1] = g end
        for _ = 1, missing do groups[#groups + 1] = "0" end
        for _, g in ipairs(t) do groups[#groups + 1] = g end
    else
        for part in ip:gmatch("[^:]+") do groups[#groups + 1] = part end
    end
    if #groups ~= 8 then
        return nil
    end
    local hex = {}
    for i = 1, 8 do
        local g = groups[i]
        if not g:match("^%x+$") or #g > 4 then
            return nil
        end
        hex[i] = string.rep("0", 4 - #g) .. g
    end
    return table.concat(hex)
end

local function parse_v6_cidr(cidr)
    local ip, bits = cidr:match("^(.+)/(%d+)$")
    if not ip or not ip:find(":", 1, true) then
        return nil
    end
    bits = tonumber(bits)
    if not bits or bits < 0 or bits > 128 then
        return nil
    end
    local hex = expand_v6(ip)
    if not hex then
        return nil
    end
    local nib = math.floor(bits / 4)  -- 4-bit granularite (bot prefix'leri /32,/48,/64 -> tam)
    return { hex = hex:sub(1, nib), nib = nib }
end

local function v6_match(entry, iphex)
    if entry.nib == 0 then
        return true
    end
    return iphex:sub(1, entry.nib) == entry.hex
end

--- bot-ranges.json'u okuyup CIDR'leri ayristirir (worker basina modul state).
local function load_ranges()
    _dyn = {}
    local f = io.open(RANGES_FILE, "r")
    if not f then
        return
    end
    local content = f:read("*a")
    f:close()

    local data = cjson.decode(content)
    if type(data) ~= "table" or type(data.bots) ~= "table" then
        return
    end

    for name, list in pairs(data.bots) do
        local e = { v4 = {}, v6 = {} }
        if type(list) == "table" then
            for _, cidr in ipairs(list) do
                if type(cidr) == "string" then
                    if cidr:find(":", 1, true) then
                        local p = parse_v6_cidr(cidr)
                        if p then e.v6[#e.v6 + 1] = p end
                    else
                        local p = parse_v4_cidr(cidr)
                        if p then e.v4[#e.v4 + 1] = p end
                    end
                end
            end
        end
        _dyn[name] = e
    end
end

--- Dosyayi en fazla RANGES_RELOAD saniyede bir yeniden yukler (dosya kucuk).
local function maybe_reload()
    local now = ngx.now()
    if _dyn ~= nil and _dyn_checked_at and (now - _dyn_checked_at) < RANGES_RELOAD then
        return
    end
    _dyn_checked_at = now
    local ok, err = pcall(load_ranges)
    if not ok then
        ngx.log(ngx.WARN, "badsector bot_verify: ranges load hata: ", err)
        _dyn = _dyn or {}
    end
end

--- IP, verilen bot adinin dinamik (resmi) aralik listesinde mi?
local function dynamic_match(ip, name)
    maybe_reload()
    local e = _dyn and _dyn[name]
    if not e then
        return false
    end
    if ip:find(":", 1, true) then
        local hex = expand_v6(ip)
        if not hex then
            return false
        end
        for _, entry in ipairs(e.v6) do
            if v6_match(entry, hex) then
                return true
            end
        end
    else
        local num = ipv4_to_num(ip)
        if not num then
            return false
        end
        for _, entry in ipairs(e.v4) do
            if v4_match(entry, num) then
                return true
            end
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

    -- Hizli yol: statik prefix VEYA worker'in gunluk guncelledigi resmi CIDR
    -- listesi (DNS yok). Dinamik liste attack mode'da da guvenle kullanilir.
    if ip_prefix_match(ip, bot.prefixes) or dynamic_match(ip, bot.name) then
        verified = true
    elseif attack_mode.is_on() then
        -- Saldiri aninda pahali rDNS yapma: sahte "Googlebot" UA'li binlerce IP
        -- bizi DNS sorgusuna bogabilir. Sadece prefix + dinamik CIDR'e guven.
        -- Bunlarin disindaki bot bu sure boyunca normal korumalardan gecer.
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
