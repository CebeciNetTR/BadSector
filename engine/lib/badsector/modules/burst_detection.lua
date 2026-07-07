local decision = require("badsector.decision")
local redis = require("badsector.redis")
local ratelimit = require("badsector.ratelimit")

local M = { name = "burst_detection", version = "1.0.0" }

local cfg = {
    enabled = true,
    window = 10,
    threshold = 50,
    key_by = "ip",
    paths = { "/*" },
    action = "rate_limit",
    fail_open = true,
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.window = tonumber(config.window) or 10
    cfg.threshold = tonumber(config.threshold) or 50
    cfg.key_by = config.key_by or "ip"
    cfg.paths = config.paths or { "/*" }
    cfg.action = config.action or "rate_limit"
    cfg.fail_open = config.fail_open ~= false
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end
    if not cfg.enabled then
        return decision.CONTINUE
    end

    if not ratelimit.rule_matches({ paths = cfg.paths, enabled = true }, ctx) then
        return decision.CONTINUE
    end

    local site_id = ctx.site and ctx.site.id or "default"
    local key = ratelimit.build_key(site_id, "burst", cfg.key_by, ctx)

    local count, err = redis.incr_window(key, cfg.window)
    if not count then
        if cfg.fail_open then
            return decision.CONTINUE
        end
        ctx:trace("burst_detection", decision.BLOCK, "Burst counter unavailable")
        return decision.block(503, "Service unavailable")
    end

    ctx.enrich.burst = { count = count, threshold = cfg.threshold, window = cfg.window }

    if count > cfg.threshold then
        ctx:trace("burst_detection", decision.BLOCK, "Burst threshold exceeded", {
            count = count,
            threshold = cfg.threshold,
        })

        if cfg.action == "block" then
            return decision.block(429, "Too Many Requests")
        end

        return decision.rate_limit(30, {
            rule_id = "burst_detection",
            count = count,
            limit = cfg.threshold,
        })
    end

    return decision.CONTINUE
end

return M
