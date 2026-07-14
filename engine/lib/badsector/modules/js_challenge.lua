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

local M = { name = "js_challenge", version = "2.0.0" }

local cfg = {
    enabled = false,
    paths = { "/*" },
    exclude_paths = { "/badsector/*" },
    pass_cookie = "bs_pass",
    pow_cookie = "bs_pow",
    difficulty = 4,
    difficulty_attack = 5,
    pass_ttl = 3600,
    ban_threshold = 3,   -- 60s icinde bu kadar cozumsuz challenge -> ban
    ban_ttl = 86400,
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled == true
    cfg.paths = config.paths or { "/*" }
    cfg.exclude_paths = config.exclude_paths or { "/badsector/*" }
    cfg.pass_cookie = config.pass_cookie or "bs_pass"
    cfg.pow_cookie = config.pow_cookie or "bs_pow"
    cfg.difficulty = tonumber(config.difficulty) or 4
    cfg.difficulty_attack = tonumber(config.difficulty_attack) or 5
    cfg.pass_ttl = tonumber(config.pass_ttl) or 3600
    cfg.ban_threshold = tonumber(config.ban_threshold) or 3
    cfg.ban_ttl = tonumber(config.ban_ttl) or 86400
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
        red:setex("bs:ban:" .. ip, cfg.ban_ttl, "1")
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
    if util.path_matches(path, cfg.exclude_paths) then
        return decision.CONTINUE
    end
    if not ratelimit.rule_matches({ paths = cfg.paths, enabled = true }, ctx) then
        return decision.CONTINUE
    end

    local headers = ctx.request.headers
    local ip = ctx.request.remote_addr
    local ua = util.header_get(headers, "User-Agent") or ""

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
            ctx:trace("js_challenge", decision.CONTINUE, "PoW cozuldu — pass veriliyor")
            return decision.custom(302, "", {
                ["Location"] = ngx.var.request_uri or path,
                ["Cache-Control"] = "no-store",
                ["Set-Cookie"] = {
                    cfg.pass_cookie .. "=" .. token .. "; Path=/; Max-Age=" .. cfg.pass_ttl .. "; HttpOnly; SameSite=Lax",
                    cfg.pow_cookie .. "=; Path=/; Max-Age=0",
                },
            })
        end
        -- Gecersiz cozum: sayac + banda dusur, yeni challenge ver
        ctx:trace("js_challenge", decision.CHALLENGE, "Gecersiz PoW cozumu: " .. tostring(err))
        record_challenge(ip)
    end

    -- 3) Yeni challenge uret
    local diff = pow.difficulty(cfg)
    local token = pow.make_challenge(ip, diff)
    if not sol then
        record_challenge(ip)
    end
    ctx:trace("js_challenge", decision.CHALLENGE, "PoW challenge (difficulty " .. diff .. ")", {
        difficulty = diff,
    })
    return decision.challenge("js", {
        token = token,
        difficulty = diff,
        pow_cookie = cfg.pow_cookie,
    })
end

return M
