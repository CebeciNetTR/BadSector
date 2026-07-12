--[[
  BadSector HAProxy Attack Mode - ban_check.lua

  Checks Redis for attack mode flag and IP bans at the HAProxy level.
  When attack mode is enabled (bs:attack_mode = 1), banned IPs (bs:ban:<ip>)
  are dropped silently before reaching the engine.

  Toggle attack mode:
    Enable:  redis-cli set bs:attack_mode 1
    Disable: redis-cli del bs:attack_mode
]]

-- Attack mode state cache (refresh every 5 seconds to reduce Redis load)
local attack_mode_cache = { value = false, expires = 0 }

-- Raw Redis GET via RESP protocol
local function redis_get(host, port, key)
    local sock = core.tcp()
    sock:settimeout(100)

    local ok = sock:connect(host, port)
    if not ok then
        return nil
    end

    local cmd = "*2\r\n$3\r\nGET\r\n$" .. #key .. "\r\n" .. key .. "\r\n"
    sock:send(cmd)

    local line = sock:receive("*l")
    if not line then
        sock:close()
        return nil
    end

    -- $-1 means key does not exist
    local len = tonumber(line:sub(2))
    if not len or len < 0 then
        sock:close()
        return nil
    end

    -- Read value + trailing CRLF
    local val = sock:receive(len + 2)
    sock:close()

    if val then
        return val:sub(1, -3)
    end
    return nil
end

-- Check attack mode with 5-second cache
local function is_attack_mode(host, port)
    local now = os.time()
    if now < attack_mode_cache.expires then
        return attack_mode_cache.value
    end
    local val = redis_get(host, port, "bs:attack_mode")
    attack_mode_cache.value = (val == "1")
    attack_mode_cache.expires = now + 5
    return attack_mode_cache.value
end

-- Register the HAProxy http-req action
core.register_action("ban_check", { "http-req" }, function(txn)
    local redis_host = os.getenv("BADSECTOR_REDIS_HOST") or "redis"
    local redis_port = tonumber(os.getenv("BADSECTOR_REDIS_PORT")) or 6379

    -- Fast path: skip everything if attack mode is off
    if not is_attack_mode(redis_host, redis_port) then
        return
    end

    -- Get the real client IP
    local ip = txn.f:src()
    if not ip or ip == "" then
        return
    end

    -- Check ban list
    local banned = redis_get(redis_host, redis_port, "bs:ban:" .. ip)
    if banned then
        core.log(core.LOG_WARNING, "badsector attack_mode: dropping banned IP " .. ip)
        txn.set_var(txn, "txn.bs_banned", true)
    end
end, 0)
