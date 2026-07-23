--[[
  JS Proof-of-Work challenge modulu.

  Akis (hepsi stateless, Redis'siz — yalnizca auto-ban icin Redis):
    1) Gecerli bs_pass cookie varsa    -> CONTINUE (hizli yol, 1 HMAC).
    2) bs_pow cozum cookie'si varsa     -> dogrula; gecerliyse bs_pass ver (302).
    3) Aksi halde                       -> imzali PoW challenge sayfasi don.

  Zorluk attack mode'da otomatik yukselir (pow.difficulty). Cozemeyen istemci
  tekrar tekrar challenge alir; auto-ban esigi asilinca banlanir -> maliyet
  IP basina birkac sayfayla sinirli kalir (sonra edge silent-drop).
]]

local decision = require("badsector.decision")
local ratelimit = require("badsector.ratelimit")
local util = require("badsector.util")
local pow = require("badsector.pow")

local M = { name = "js_challenge", version = "2.1.0" }

-- Favicon vb. exclude_paths'te olmasa bile challenge/ban sayacina girmesin.
local DEFAULT_EXCLUDE_PATHS = {
    "/badsector/*",
    "/favicon.ico",
    "/favicon-32x32.png",
    "/favicon-16x16.png",
    "/apple-touch-icon.png",
    "/apple-touch-icon-precomposed.png",
    "/robots.txt",
    "/sitemap.xml",
}

local STATIC_EXT = {
    ico = true, png = true, jpg = true, jpeg = true, gif = true, webp = true,
    svg = true, bmp = true, avif = true, css = true, js = true, mjs = true,
    map = true, woff = true, woff2 = true, ttf = true, eot = true, otf = true,
    mp4 = true, webm = true, mp3 = true, wav = true, pdf = true, zip = true,
    txt = true, xml = true, json = true, webmanifest = true,
}

local cfg = {
    enabled = false,
    paths = { "/*" },
    exclude_paths = DEFAULT_EXCLUDE_PATHS,
    pass_cookie = "bs_pass",
    pow_cookie = "bs_pow",
    difficulty = 4,
    difficulty_attack = 5,
    pass_ttl = 3600,
    ban_threshold = 5,   -- 60s icinde bu kadar cozumsuz challenge -> ban
    ban_ttl = 86400,
    template = "",       -- ozel challenge HTML (bos ise varsayilan sablon)
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled == true
    cfg.paths = config.paths or { "/*" }
    cfg.exclude_paths = config.exclude_paths or DEFAULT_EXCLUDE_PATHS
    cfg.pass_cookie = config.pass_cookie or "bs_pass"
    cfg.pow_cookie = config.pow_cookie or "bs_pow"
    cfg.difficulty = tonumber(config.difficulty) or 4
    cfg.difficulty_attack = tonumber(config.difficulty_attack) or 5
    cfg.pass_ttl = tonumber(config.pass_ttl) or 3600
    cfg.ban_threshold = tonumber(config.ban_threshold) or 5
    cfg.ban_ttl = tonumber(config.ban_ttl) or 86400
    cfg.template = type(config.template) == "string" and config.template or ""
end

--- Statik asset mi? (favicon.ico, *.css, *.js, ...) — challenge uygulama / sayma.
local function is_static_asset(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    -- querystring at
    local p = path:match("^([^?]*)") or path
    local ext = p:match("%.([%w]+)$")
    if ext and STATIC_EXT[ext:lower()] then
        return true
    end
    return false
end

--- HTML navigasyon mu? Asset ve XHR sayaca yazilmasin; sadece belge gecisi.
local function is_document_navigation(headers)
    headers = headers or {}
    local dest = util.header_get(headers, "Sec-Fetch-Dest")
    if dest then
        dest = dest:lower()
        if dest == "document" or dest == "iframe" then
            return true
        end
        -- empty / cors / image / style / script / ... -> sayma
        if dest ~= "" then
            return false
        end
    end
    local accept = util.header_get(headers, "Accept") or ""
    if accept:find("text/html", 1, true) then
        return true
    end
    -- Eski istemci / header yok: ana path icin say (guvenli taraf: say)
    return true
end

--- Cookie header'indan tek bir cookie degerini cikarir.
local function get_cookie(headers, name)
    local c = util.header_get(headers, "Cookie")
    if not c then
        return nil
    end
    for kv in c:gmatch("[^;]+") do
        local k, v = kv:match("^%s*([^=]+)=(.*)$")
        if k == name then
            return v
        end
    end
    return nil
end

--- Cozumsuz challenge sayacini artir; esik asilirsa IP'yi banla.
local function record_challenge(ip)
    if not ip or ip == "" then
        return
    end
    local redis = require("badsector.redis")
    local red = redis.connect()
    if not red then
        return
    end
    local fail_key = "bs:js_fail:" .. ip
    local count = red:incr(fail_key)
    if count == 1 then
        red:expire(fail_key, 60)
    end
    if count and count >= cfg.ban_threshold then
        local ban_strikes = require("badsector.ban_strikes")
        ban_strikes.apply_ban(ip, "js_challenge", cfg.ban_ttl)
        ngx.log(ngx.WARN, "badsector: IP " .. ip .. " banlandi (cozumsuz JS challenge x" .. tostring(count) .. ")")
    end
    redis.keepalive(red)
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end
    if not cfg.enabled then
        return decision.CONTINUE
    end

    local path = ctx.request.path
    -- 1) Statik asset + exclude: challenge yok, sayac yok (favicon ban bug'i).
    if is_static_asset(path) or util.path_matches(path, cfg.exclude_paths) then
        return decision.CONTINUE
    end
    if not ratelimit.rule_matches({ paths = cfg.paths, enabled = true }, ctx) then
        return decision.CONTINUE
    end

    local headers = ctx.request.headers
    local ip = ctx.request.remote_addr
    local ua = util.header_get(headers, "User-Agent") or ""
    local count_fail = is_document_navigation(headers)

    -- 1) Gecerli pass cookie -> hizli yol
    local pass_val = get_cookie(headers, cfg.pass_cookie)
    if pass_val and pow.verify_pass(ip, ua, pass_val) then
        ctx:trace("js_challenge", decision.CONTINUE, "PoW pass gecerli")
        return decision.CONTINUE
    end

    -- 2) Cozum gonderilmis -> dogrula
    local sol = get_cookie(headers, cfg.pow_cookie)
    if sol then
        local ok, err = pow.verify_solution(ip, sol)
        if ok then
            local token = pow.make_pass(ip, ua, cfg.pass_ttl)
            local dest = ngx.var.request_uri or path or "/"
            ctx:trace("js_challenge", decision.CONTINUE, "PoW cozuldu — pass veriliyor")
            -- REDIRECT + Set-Cookie: bos 302 govdesi / "block" header flash'ini onler.
            return decision.redirect(dest, 302, {
                ["Cache-Control"] = "no-store",
                ["Set-Cookie"] = {
                    cfg.pass_cookie .. "=" .. token .. "; Path=/; Max-Age=" .. cfg.pass_ttl .. "; HttpOnly; SameSite=Lax",
                    cfg.pow_cookie .. "=; Path=/; Max-Age=0",
                },
            })
        end
        -- Gecersiz cozum: her zaman say (kotuye kullanim)
        ctx:trace("js_challenge", decision.CHALLENGE, "Gecersiz PoW cozumu: " .. tostring(err))
        record_challenge(ip)
    end

    -- 3) Yeni challenge uret — sayac sadece belge navigasyonunda
    local diff = pow.difficulty(cfg)
    local token = pow.make_challenge(ip, diff)
    if not sol and count_fail then
        record_challenge(ip)
    end
    ctx:trace("js_challenge", decision.CHALLENGE, "PoW challenge (difficulty " .. diff .. ")", {
        difficulty = diff,
    })
    return decision.challenge("js", {
        token = token,
        difficulty = diff,
        pow_cookie = cfg.pow_cookie,
        template = cfg.template,
    })
end

return M
