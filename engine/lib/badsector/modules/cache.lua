local decision = require("badsector.decision")

local M = { name = "cache", version = "1.0.0" }

local cfg = { enabled = false, ttl = 60 }

function M.init(config) M.reload(config) end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled == true
    cfg.ttl = config.ttl or 60
end

function M.run(ctx, config)
    if config then M.reload(config) end
    if not cfg.enabled then
        return decision.CONTINUE
    end
    ctx:trace("cache", decision.CONTINUE, "cache pass-through (not yet storing responses)")
    return decision.CONTINUE
end

return M
