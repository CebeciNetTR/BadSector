--[[
  BadSector Request Metrics

  Increments Redis counters on every request for dashboard aggregation.
]]

local redis = require("badsector.redis")

local _M = {}

local GLOBAL_KEY = "badsector:metrics:global"
local DECISIONS_KEY = "badsector:metrics:decisions"

local function incr_hash(key, field, amount)
    local red, err = redis.connect()
    if not red then
        return
    end
    red:hincrby(key, field, amount or 1)
    redis.keepalive(red)
end

--- Record request metrics after pipeline completes.
---@param site_id string
---@param ctx table RequestContext
function _M.record(site_id, ctx)
    local decision = ctx.decision or { action = "ALLOW" }
    local action = decision.action or "ALLOW"

    incr_hash(GLOBAL_KEY, "requests", 1)
    incr_hash(DECISIONS_KEY, action, 1)

    if site_id and site_id ~= "" then
        incr_hash("badsector:metrics:site:" .. site_id, "requests", 1)
        incr_hash("badsector:metrics:site:" .. site_id, action, 1)
    end
end

return _M
