--[[
  BadSector Live Request Trace Buffer

  Stores recent request traces in Redis for dashboard explainability.
  Enabled per site via settings.live_trace.
]]

local cjson = require("cjson.safe")
local redis = require("badsector.redis")

local _M = {}

local max_entries = tonumber(os.getenv("BADSECTOR_TRACE_BUFFER_SIZE")) or 100
local ttl_seconds = tonumber(os.getenv("BADSECTOR_TRACE_TTL")) or 3600

local function trace_key(site_id)
    return "badsector:trace:" .. site_id
end

--- Record a completed request trace.
---@param site_id string
---@param ctx table RequestContext
function _M.record(site_id, ctx)
    if not site_id or site_id == "" then
        return
    end

    local req = ctx.request or {}
    local decision = ctx.decision or { action = "ALLOW" }

    local payload = {
        id = req.id,
        ts = ngx.time(),
        method = req.method,
        path = req.path or req.uri,
        host = req.host,
        remote_addr = req.remote_addr,
        user_agent = (req.headers or {})["User-Agent"] or (req.headers or {})["user-agent"],
        decision = decision.action,
        status = decision.status,
        duration_ms = math.floor(((ngx.now() - (ctx._start or ngx.now())) * 1000) + 0.5),
        steps = ctx.trace or {},
    }

    local json = cjson.encode(payload)
    if not json then
        return
    end

    local red, err = redis.connect()
    if not red then
        ngx.log(ngx.DEBUG, "badsector trace: redis unavailable: ", err or "unknown")
        return
    end

    local key = trace_key(site_id)
    red:lpush(key, json)
    red:ltrim(key, 0, max_entries - 1)
    red:expire(key, ttl_seconds)
    redis.keepalive(red)
end

return _M
