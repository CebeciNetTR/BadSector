local decision = require("badsector.decision")
local ratelimit = require("badsector.ratelimit")
local util = require("badsector.util")

local M = { name = "cookie_challenge", version = "1.0.0" }

local cfg = {
    enabled = false,
    paths = { "/*" },
    exclude_paths = { "/badsector/*" },
    cookie_name = "bs_verified",
    cookie_ttl = 86400,
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled == true
    cfg.paths = config.paths or { "/*" }
    cfg.exclude_paths = config.exclude_paths or { "/badsector/*" }
    cfg.cookie_name = config.cookie_name or "bs_verified"
    cfg.cookie_ttl = tonumber(config.cookie_ttl) or 86400
end

local function cookie_verified(headers, name)
    local cookie = util.header_get(headers, "Cookie") or ""
    return cookie:find(name .. "=", 1, true) ~= nil
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end
    if not cfg.enabled then
        return decision.CONTINUE
    end

    if util.path_matches(ctx.request.path, cfg.exclude_paths) then
        return decision.CONTINUE
    end

    if not ratelimit.rule_matches({ paths = cfg.paths, enabled = true }, ctx) then
        return decision.CONTINUE
    end

    if cookie_verified(ctx.request.headers, cfg.cookie_name) then
        ctx:trace("cookie_challenge", decision.CONTINUE, "Cookie challenge passed")
        return decision.CONTINUE
    end

    ctx:trace("cookie_challenge", decision.CHALLENGE, "Cookie challenge required")
    return decision.challenge("cookie", {
        cookie_name = cfg.cookie_name,
        cookie_ttl = cfg.cookie_ttl,
    })
end

return M
