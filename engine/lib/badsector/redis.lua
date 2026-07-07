--[[
  BadSector Redis Client

  Connection-pooled Redis access for rate limiting and counters.
  Falls back gracefully when Redis is unavailable.
]]

local _M = {}

local redis_host = os.getenv("BADSECTOR_REDIS_HOST") or "127.0.0.1"
local redis_port = tonumber(os.getenv("BADSECTOR_REDIS_PORT")) or 6379
local redis_timeout = tonumber(os.getenv("BADSECTOR_REDIS_TIMEOUT")) or 100
local redis_password = os.getenv("BADSECTOR_REDIS_PASSWORD")

local pool_size = tonumber(os.getenv("BADSECTOR_REDIS_POOL_SIZE")) or 100
local pool_idle = tonumber(os.getenv("BADSECTOR_REDIS_POOL_IDLE")) or 10000

local enabled = true

--- Atomic fixed-window increment script.
--- KEYS[1] = counter key, ARGV[1] = window seconds
local INCR_SCRIPT = [[
local c = redis.call('INCR', KEYS[1])
if c == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return c
]]

--- Connect to Redis with connection pooling.
---@return table|nil red
---@return string|nil err
function _M.connect()
    local loaded, redis_mod = pcall(require, "resty.redis")
    if not loaded then
        return nil, "resty.redis not available"
    end

    local red = redis_mod:new()
    red:set_timeout(redis_timeout)

    local ok, err = red:connect(redis_host, redis_port)

    if not ok then
        return nil, err
    end

    if redis_password and redis_password ~= "" then
        ok, err = red:auth(redis_password)
        if not ok then
            red:close()
            return nil, err
        end
    end

    return red
end

--- Return connection to pool.
---@param red table
function _M.keepalive(red)
    if not red then
        return
    end
    local ok, err = red:set_keepalive(pool_idle, pool_size)
    if not ok then
        ngx.log(ngx.WARN, "badsector redis keepalive: ", err)
    end
end

--- Atomic increment with TTL window.
---@param key string
---@param window number Window in seconds
---@return number|nil count
---@return string|nil err
function _M.incr_window(key, window)
    local red, err = _M.connect()
    if not red then
        return nil, err
    end

    local count, eval_err = red:eval(INCR_SCRIPT, 1, key, window)
    _M.keepalive(red)

    if not count then
        return nil, eval_err
    end

    return tonumber(count), nil
end

--- Get TTL remaining for a key (retry-after hint).
---@param key string
---@return number|nil
function _M.ttl(key)
    local red, err = _M.connect()
    if not red then
        return nil
    end

    local ttl, ttl_err = red:ttl(key)
    _M.keepalive(red)

    if not ttl or ttl < 0 then
        return window_fallback()
    end

    return ttl
end

function window_fallback()
    return 60
end

--- Check if Redis is configured and reachable (worker init probe).
---@return boolean
function _M.available()
    if not enabled then
        return false
    end

    local red, err = _M.connect()
    if not red then
        ngx.log(ngx.WARN, "badsector redis unavailable: ", err or "unknown")
        return false
    end

    local ok, ping_err = red:ping()
    _M.keepalive(red)

    if ok == "PONG" or ok == "pong" or ok == true then
        return true
    end

    ngx.log(ngx.WARN, "badsector redis ping failed: ", ping_err or "unknown")
    return false
end

--- Override connection settings (for module init from config).
---@param opts table|nil
function _M.configure(opts)
    opts = opts or {}
    if opts.host then redis_host = opts.host end
    if opts.port then redis_port = opts.port end
    if opts.timeout then redis_timeout = opts.timeout end
    if opts.password then redis_password = opts.password end
    if opts.enabled == false then enabled = false end
end

return _M
