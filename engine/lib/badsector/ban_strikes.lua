--- Ban olay sayaci: 24s icinde N veya 7 gun icinde M ban → kalici ban (TTL yok).
local _M = {}

local DAY_LIMIT = tonumber(os.getenv("BADSECTOR_BAN_STRIKES_DAY")) or 3
local WEEK_LIMIT = tonumber(os.getenv("BADSECTOR_BAN_STRIKES_WEEK")) or 7
local DAY_TTL = 86400
local WEEK_TTL = 604800

--- @return boolean permanent
--- @return number day_strikes
--- @return number week_strikes
function _M.record(ip)
    if not ip or ip == "" then
        return false, 0, 0
    end
    local trusted = require("badsector.trusted_ips")
    if trusted.is(ip) then
        return false, 0, 0
    end

    local redis = require("badsector.redis")
    local red = redis.connect()
    if not red then
        return false, 0, 0
    end

    local day_key = "bs:ban_strikes:day:" .. ip
    local week_key = "bs:ban_strikes:week:" .. ip
    local day = red:incr(day_key)
    if day == 1 then
        red:expire(day_key, DAY_TTL)
    end
    local week = red:incr(week_key)
    if week == 1 then
        red:expire(week_key, WEEK_TTL)
    end
    redis.keepalive(red)

    local permanent = (day >= DAY_LIMIT) or (week >= WEEK_LIMIT)
    return permanent, day, week
end

--- Ban kaydi + strike sayaci. Kalici ban: bs:ban:IP TTL yok, deger "permanent:<reason>".
--- @return boolean permanent
function _M.apply_ban(ip, reason, temp_ttl)
    reason = reason or "1"
    temp_ttl = tonumber(temp_ttl) or 86400

    local permanent, day, week = _M.record(ip)
    if not ip or ip == "" then
        return false
    end

    local redis = require("badsector.redis")
    local red = redis.connect()
    if not red then
        return permanent
    end

    local dict = ngx.shared.badsector_bans
    if permanent then
        red:set("bs:ban:" .. ip, "permanent:" .. reason)
        if dict then
            dict:set(ip, 1, 300)
        end
        ngx.log(ngx.WARN, "badsector: IP " .. ip .. " KALICI ban (strikes day="
            .. tostring(day) .. " week=" .. tostring(week) .. " reason=" .. reason .. ")")
    else
        red:setex("bs:ban:" .. ip, temp_ttl, reason)
        if dict then
            dict:set(ip, 1, 30)
        end
    end
    redis.keepalive(red)
    return permanent
end

return _M
