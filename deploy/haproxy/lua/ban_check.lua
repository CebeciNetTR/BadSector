--[[
  BadSector HAProxy Attack Mode - ban_check.lua

  MIMARI (onemli): HAProxy Lua'da socket I/O yalnizca "yield" edilebilen
  baglamlarda yapilabilir. http-request action'i socket icin yield EDEMEZ
  ("yield not allowed" hatasi). Bu yuzden TUM Redis I/O'su arka plan task'inda
  (core.register_task) yapilir; istek basina action ise SADECE bellekteki
  global'leri okur (socket yok -> yield yok, cok hizli, DDoS'a dayanikli).

  Arka plan task'i periyodik olarak:
    1. bs:attack_mode  -> _attack_mode (global bayrak)
    2. biriken IP hit'leri -> ZINCRBY bs:ip_hits (watcher bu seti okur)
    3. attack acikken   -> SCAN bs:ban:* -> _bans (bellekte ban tablosu)

  Istek basina action:
    - _hits[ip]++  (bellek)
    - txn.bs_attack_mode = _attack_mode
    - attack + banli ise txn.bs_banned = true

  Attack mode toggle:  redis-cli set bs:attack_mode 1  |  redis-cli del bs:attack_mode
]]

local POLL_MS   = tonumber(os.getenv("BADSECTOR_BAN_POLL_MS")) or 2000
local BAN_CAP   = tonumber(os.getenv("BADSECTOR_BAN_CAP")) or 200000
local HITS_CAP  = tonumber(os.getenv("BADSECTOR_HITS_CAP")) or 200000

-- Global trusted IPs (BADSECTOR_TRUSTED_IPS=ip1,ip2 — kodda sabit yok)
local _trusted = {}
do
    local raw = os.getenv("BADSECTOR_TRUSTED_IPS") or ""
    for part in raw:gmatch("[^,]+") do
        local ip = part:match("^%s*(.-)%s*$")
        if ip and ip ~= "" then
            _trusted[ip] = true
        end
    end
end

-- Global durum (lua-load tek Lua state + kilit kullandigi icin thread'ler arasi guvenli)
local _attack_mode = false
local _hits = {}   -- ip -> biriken sayac (task flush eder)
local _hits_n = 0  -- _hits'teki farkli ip sayisi (Redis erisilemezse OOM korumasi)
local _bans = {}   -- ip -> true (task yeniler)

local warned_bad_host = false

local function is_ipv4(s)
    if type(s) ~= "string" then return false end
    return s:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

-- ---- RESP (Redis protokolu) yardimcilari -  � YALNIZCA task baglaminda kullanilir ----

local function send_cmd(sock, args)
    local parts = { "*" .. #args .. "\r\n" }
    for _, a in ipairs(args) do
        a = tostring(a)
        parts[#parts + 1] = "$" .. #a .. "\r\n" .. a .. "\r\n"
    end
    return sock:send(table.concat(parts))
end

-- Tek bir RESP yanitini okur (+simple, -error, :int, $bulk, *array; ic ice)
local function read_reply(sock)
    local line = sock:receive("*l")
    if not line or line == "" then
        return nil, "no reply"
    end
    local p = line:sub(1, 1)
    local rest = line:sub(2)

    if p == "+" then
        return rest
    elseif p == "-" then
        return nil, rest
    elseif p == ":" then
        return tonumber(rest)
    elseif p == "$" then
        local len = tonumber(rest)
        if not len or len < 0 then
            return nil
        end
        local data = sock:receive(len + 2)  -- veri + CRLF
        if not data then
            return nil
        end
        return data:sub(1, len)
    elseif p == "*" then
        local n = tonumber(rest)
        if not n or n < 0 then
            return nil
        end
        local arr = {}
        for i = 1, n do
            arr[i] = read_reply(sock)
        end
        return arr
    end
    return nil, "bad prefix"
end

local function redis_do(sock, args)
    if not send_cmd(sock, args) then
        return nil, "send failed"
    end
    return read_reply(sock)
end

-- ---- Task adimlari ----

local function poll_attack_mode(sock)
    local v = redis_do(sock, { "GET", "bs:attack_mode" })
    _attack_mode = (v == "1")
end

local function flush_hits(sock)
    -- Anlik snapshot al ve sifirla (kilit altinda tek thread)
    local snapshot = _hits
    _hits = {}
    _hits_n = 0

    -- Pipeline: tek tek round-trip yerine komutlari batch halinde gonder, sonra
    -- yanitlari topluca oku. 80k+ IP'de N round-trip'i N/BATCH'e dusurur; flood
    -- altinda Redis'i ve Lua task'ini bogmaz (incident kok nedeni).
    local BATCH = 1000
    local buf = {}
    local pending = 0

    local function flush_batch()
        if pending == 0 then
            return
        end
        if sock:send(table.concat(buf)) then
            for _ = 1, pending do
                read_reply(sock)
            end
        end
        buf = {}
        pending = 0
    end

    for ip, count in pairs(snapshot) do
        if count > 0 then
            local args = { "ZINCRBY", "bs:ip_hits", count, ip }
            buf[#buf + 1] = "*" .. #args .. "\r\n"
            for _, a in ipairs(args) do
                a = tostring(a)
                buf[#buf + 1] = "$" .. #a .. "\r\n" .. a .. "\r\n"
            end
            pending = pending + 1
            if pending >= BATCH then
                flush_batch()
            end
        end
    end
    flush_batch()
end

local function refresh_bans(sock)
    if not _attack_mode then
        _bans = {}
        return
    end
    local new_bans = {}
    local cursor = "0"
    local total = 0
    local iterations = 0
    repeat
        local reply = redis_do(sock, { "SCAN", cursor, "MATCH", "bs:ban:*", "COUNT", "500" })
        if type(reply) ~= "table" then
            break
        end
        cursor = reply[1]
        local keys = reply[2]
        if type(keys) == "table" then
            for _, key in ipairs(keys) do
                local ip = key:gsub("^bs:ban:", "")
                new_bans[ip] = true
                total = total + 1
                if total >= BAN_CAP then
                    cursor = "0"
                    break
                end
            end
        end
        iterations = iterations + 1
    until cursor == "0" or iterations > 5000
    _bans = new_bans
end

local function task_tick()
    local host = os.getenv("BADSECTOR_REDIS_HOST") or "redis"
    local port = tonumber(os.getenv("BADSECTOR_REDIS_PORT")) or 6379

    if not is_ipv4(host) then
        if not warned_bad_host then
            warned_bad_host = true
            core.log(core.LOG_ERR, "badsector ban_check: BADSECTOR_REDIS_HOST '"
                .. tostring(host) .. "' bir IP degil; Redis atlaniyor (attack-mode devre disi)")
        end
        return
    end

    local sock = core.tcp()
    sock:settimeout(1000)
    if not sock:connect(host, port) then
        return
    end

    poll_attack_mode(sock)
    flush_hits(sock)
    refresh_bans(sock)
    sock:close()
end

-- Arka plan task'i: scheduler basladiginda calisir, sonsuz dongu + msleep.
core.register_task(function()
    while true do
        local ok, err = pcall(task_tick)
        if not ok then
            core.log(core.LOG_WARNING, "badsector ban_check task error: " .. tostring(err))
        end
        core.msleep(POLL_MS)
    end
end)

-- Istek basina action: SADECE bellek erisimi (socket yok, yield yok).
core.register_action("ban_check", { "http-req" }, function(txn)
    local ip = txn.f:src()
    if ip and ip ~= "" and not _trusted[ip] then
        local cur = _hits[ip]
        if cur then
            _hits[ip] = cur + 1
        elseif _hits_n < HITS_CAP then
            -- Yeni IP: yalnizca kapasite dahilindeyse ekle (Redis erisilemezse
            -- flush olmaz; sinirsiz IP birikimini engelle).
            _hits[ip] = 1
            _hits_n = _hits_n + 1
        end
        if _attack_mode and _bans[ip] then
            txn.set_var(txn, "txn.bs_banned", true)
        end
    end
    txn.set_var(txn, "txn.bs_attack_mode", _attack_mode)
end, 0)
