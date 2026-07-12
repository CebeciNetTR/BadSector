--[[
  BadSector HAProxy Attack Mode - ban_check.lua

  1. Her IP icin Redis sorted set (bs:ip_hits) uzerinde hit sayar.
     Verimlilik icin her BATCH_SIZE istekte bir Redis'e yazar (per thread).
  2. Attack mode (bs:attack_mode=1) aktifken:
     - bs:ban:<ip> kontrolu yapar
     - Banli IP'leri engine'e ulastirmadan silent-drop eder

  Attack mode toggle:
    Ac:   redis-cli set bs:attack_mode 1
    Kapat: redis-cli del bs:attack_mode
]]

local BATCH_SIZE = 10  -- Her N istekte bir Redis'e yaz (per thread)

-- Attack mode durumu cache (5 saniyede bir yenilenir)
local attack_mode_cache = { value = false, expires = 0 }

-- Thread-yerel hit sayaci (HAProxy thread'leri arasinda paylasilmaz)
local hit_counter = {}

-- Redis GET (RESP protokolü)
local function redis_get(host, port, key)
    local sock = core.tcp()
    sock:settimeout(100)
    if not sock:connect(host, port) then return nil end

    local cmd = "*2\r\n$3\r\nGET\r\n$" .. #key .. "\r\n" .. key .. "\r\n"
    sock:send(cmd)

    local line = sock:receive("*l")
    if not line then sock:close(); return nil end

    local len = tonumber(line:sub(2))
    if not len or len < 0 then sock:close(); return nil end

    local val = sock:receive(len + 2)
    sock:close()
    if val then return val:sub(1, -3) end
    return nil
end

-- Redis ZINCRBY - sorted set hit sayaci (toplu yazma)
local function redis_zincrby_batch(host, port, ip, amount)
    local sock = core.tcp()
    sock:settimeout(50)
    if not sock:connect(host, port) then return end

    local key = "bs:ip_hits"
    local amt = tostring(amount)
    -- ZINCRBY bs:ip_hits <amount> <ip>
    local cmd = "*4\r\n$8\r\nZINCRBY\r\n$" .. #key .. "\r\n" .. key ..
                "\r\n$" .. #amt .. "\r\n" .. amt ..
                "\r\n$" .. #ip .. "\r\n" .. ip .. "\r\n"
    sock:send(cmd)
    sock:receive("*l")  -- yaniti oku (bloklamamak icin)
    sock:close()
end

-- IP hit'ini sayar, BATCH_SIZE dolunca Redis'e yazar
local function track_hit(host, port, ip)
    local count = (hit_counter[ip] or 0) + 1
    hit_counter[ip] = count

    if count >= BATCH_SIZE then
        hit_counter[ip] = 0
        redis_zincrby_batch(host, port, ip, BATCH_SIZE)
    end
end

-- Attack mode durumunu cache ile kontrol et
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

-- HAProxy http-req action
core.register_action("ban_check", { "http-req" }, function(txn)
    local redis_host = os.getenv("BADSECTOR_REDIS_HOST") or "redis"
    local redis_port = tonumber(os.getenv("BADSECTOR_REDIS_PORT")) or 6379

    local ip = txn.f:src()
    if not ip or ip == "" then return end

    -- Her zaman hit say (attack mode bagimsiz)
    track_hit(redis_host, redis_port, ip)

    -- Attack mode kapali ise hizli cikis
    if not is_attack_mode(redis_host, redis_port) then
        return
    end

    -- Ban listesini kontrol et
    local banned = redis_get(redis_host, redis_port, "bs:ban:" .. ip)
    if banned then
        core.log(core.LOG_WARNING, "badsector attack_mode: dropping banned IP " .. ip)
        txn.set_var(txn, "txn.bs_banned", true)
    end
end, 0)
