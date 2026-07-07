--[[
  BadSector Rate Limit Engine

  Fixed-window counter with Redis primary store and shared dict fallback.
  Designed for < 0.2ms local / < 1ms Redis pipelined per check.
]]

local redis = require("badsector.redis")

local _M = {}

local dict = ngx.shared.badsector_counters

--- Parse window string ("60", "60s", "1m", "1h") to seconds.
---@param window any
---@return number
function _M.parse_window(window)
    if type(window) == "number" then
        return window
    end

    local s = tostring(window or "60")
    local n, unit = s:match("^(%d+)([smh]?)$")
    n = tonumber(n) or 60
    unit = unit or "s"

    if unit == "m" then return n * 60 end
    if unit == "h" then return n * 3600 end
    return n
end

--- Build rate limit key from request context.
---@param site_id string
---@param rule_id string
---@param key_by string
---@param ctx table
---@return string
function _M.build_key(site_id, rule_id, key_by, ctx)
    local parts = { "bs", "rl", site_id or "default", rule_id or "rule" }

    if key_by == "global" then
        parts[#parts + 1] = "global"
    elseif key_by == "ip" then
        parts[#parts + 1] = ctx.request.remote_addr
    elseif key_by == "ip_path" then
        parts[#parts + 1] = ctx.request.remote_addr .. ":" .. ctx.request.path
    elseif key_by == "host" then
        parts[#parts + 1] = ctx.request.host or "unknown"
    elseif key_by == "header" then
        local name = ctx._rate_header_name or "authorization"
        local val = ctx.request.headers[name] or ctx.request.headers[name:lower()] or "-"
        parts[#parts + 1] = name .. ":" .. val
    elseif key_by == "cookie" then
        local name = ctx._rate_cookie_name or "session"
        parts[#parts + 1] = name .. ":" .. (ctx.request.cookies or "-")
    else
        parts[#parts + 1] = ctx.request.remote_addr
    end

    return table.concat(parts, ":")
end

--- Increment counter in shared dict (single-node fallback).
---@param key string
---@param window number
---@return number|nil count
---@return string|nil err
function _M.incr_shared(key, window)
    if not dict then
        return nil, "shared dict unavailable"
    end

    local count, err = dict:incr(key, 1, 0, window)
    if not count then
        return nil, err
    end

    return count, nil
end

--- Check rate limit for a key.
---@param opts table { key, limit, window, burst, use_redis, fail_mode }
---@return boolean allowed
---@return table info { count, limit, remaining, retry_after, backend }
function _M.check(opts)
    local key = opts.key
    local limit = tonumber(opts.limit) or 100
    local burst = tonumber(opts.burst) or 0
    local window = _M.parse_window(opts.window)
    local effective_limit = limit + burst
    local use_redis = opts.use_redis ~= false
    local fail_mode = opts.fail_mode or "open"

    local count, err, backend

    if use_redis then
        count, err = redis.incr_window(key, window)
        backend = "redis"
    end

    if not count then
        count, err = _M.incr_shared(key, window)
        backend = "shared_dict"
    end

    if not count then
        ngx.log(ngx.WARN, "badsector ratelimit: no backend available: ", err or "unknown")
        if fail_mode == "closed" then
            return false, {
                count = effective_limit + 1,
                limit = limit,
                remaining = 0,
                retry_after = window,
                backend = "none",
                error = err,
            }
        end
        return true, {
            count = 0,
            limit = limit,
            remaining = limit,
            retry_after = 0,
            backend = "none",
            bypass = true,
        }
    end

    local remaining = math.max(effective_limit - count, 0)
    local allowed = count <= effective_limit

    local retry_after = 0
    if not allowed then
        retry_after = window
        if backend == "redis" then
            local ttl = redis.ttl(key)
            if ttl and ttl > 0 then
                retry_after = ttl
            end
        end
    end

    return allowed, {
        count = count,
        limit = limit,
        burst = burst,
        effective_limit = effective_limit,
        remaining = allowed and remaining or 0,
        retry_after = retry_after,
        backend = backend,
        window = window,
    }
end

--- Match rule against request path and method.
---@param rule table
---@param ctx table
---@return boolean
function _M.rule_matches(rule, ctx)
    if rule.enabled == false then
        return false
    end

    if rule.methods and #rule.methods > 0 then
        local matched = false
        for _, m in ipairs(rule.methods) do
            if ctx.request.method == m then
                matched = true
                break
            end
        end
        if not matched then
            return false
        end
    end

    if rule.paths and #rule.paths > 0 then
        local path = ctx.request.path
        local matched = false
        for _, pattern in ipairs(rule.paths) do
            if pattern == "/*" or pattern == "*" then
                matched = true
                break
            end
            if pattern:sub(-1) == "*" then
                local prefix = pattern:sub(1, -2)
                if path:sub(1, #prefix) == prefix then
                    matched = true
                    break
                end
            elseif path == pattern then
                matched = true
                break
            end
        end
        if not matched then
            return false
        end
    end

    return true
end

return _M
