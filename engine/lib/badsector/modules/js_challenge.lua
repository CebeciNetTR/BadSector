local decision = require("badsector.decision")
local ratelimit = require("badsector.ratelimit")
local util = require("badsector.util")

local M = { name = "js_challenge", version = "1.0.0" }

local cfg = {
    enabled = false,
    paths = { "/*" },
    exclude_paths = { "/badsector/*" },
    cookie_name = "bs_js_ok",
    cookie_ttl = 3600,
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled == true
    cfg.paths = config.paths or { "/*" }
    cfg.exclude_paths = config.exclude_paths or { "/badsector/*" }
    cfg.cookie_name = config.cookie_name or "bs_js_ok"
    cfg.cookie_ttl = tonumber(config.cookie_ttl) or 3600
end

local function cookie_present(headers, name)
    local cookie = util.header_get(headers, "Cookie") or ""
    local pattern = name .. "=1"
    return cookie:find(pattern, 1, true) ~= nil
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

    if cookie_present(ctx.request.headers, cfg.cookie_name) then
        ctx:trace("js_challenge", decision.CONTINUE, "JS challenge passed")
        return decision.CONTINUE
    end

    -- Redis auto-ban on repeated challenge requests
    local redis = require("badsector.redis")
    local red = redis.connect()
    if red then
        local ip = ctx.request.remote_addr
        local fail_key = "bs:js_fail:" .. ip
        local count, err = red:incr(fail_key)
        if count == 1 then
            red:expire(fail_key, 60)
        end
        if count and count > 5 then
            red:setex("bs:ban:" .. ip, 7200, "1")
            ngx.log(ngx.WARN, "badsector: IP " .. ip .. " banned for 2 hours due to JS challenge failure")
        end
        redis.keepalive(red)
    end

    ctx:trace("js_challenge", decision.CHALLENGE, "JS challenge required")
    return decision.challenge("js", {
        cookie_name = cfg.cookie_name,
        cookie_ttl = cfg.cookie_ttl,
    })
end

return M
