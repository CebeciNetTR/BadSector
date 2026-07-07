local decision = require("badsector.decision")
local redis = require("badsector.redis")

local M = { name = "threat_intel", version = "1.0.0" }

local cfg = {
    enabled = true,
    redis_key = "badsector:threat_intel:bad",
    fail_open = true,
}

function M.init(config) M.reload(config) end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.redis_key = config.redis_key or "badsector:threat_intel:bad"
    cfg.fail_open = config.fail_open ~= false
end

function M.run(ctx, config)
    if config then M.reload(config) end
    if not cfg.enabled then return decision.CONTINUE end

    local ip = ctx.request.remote_addr
    if not ip then return decision.CONTINUE end

    local red, err = redis.connect()
    if not red then
        if cfg.fail_open then return decision.CONTINUE end
        return decision.block(503, "Service unavailable")
    end

    local ok, is_member = red:sismember(cfg.redis_key, ip)
    redis.keepalive(red)

    if not ok then
        if cfg.fail_open then return decision.CONTINUE end
        return decision.block(503, "Service unavailable")
    end

    if is_member == 1 then
        ctx.enrich.threat_intel = { matched = true, source = "redis" }
        ctx:trace("threat_intel", decision.BLOCK, "IP matched threat feed")
        return decision.block(403, "Access denied")
    end

    return decision.CONTINUE
end

return M
