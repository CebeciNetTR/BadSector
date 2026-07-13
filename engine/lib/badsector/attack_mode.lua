--[[
  BadSector Attack Mode durumu (motor tarafi)

  HAProxy ile ayni Redis bayragini (bs:attack_mode) okur. Her istekte Redis'i
  dovmemek icin sonucu paylasimli bellekte (badsector_counters) ~5s cache'ler.

  Kullanim:
    local attack_mode = require("badsector.attack_mode")
    if attack_mode.is_on() then ... end
]]

local redis = require("badsector.redis")

local _M = {}

local CACHE_KEY = "bs_attack_mode_flag"
local TTL = tonumber(os.getenv("BADSECTOR_ATTACK_MODE_TTL")) or 5

local function dict()
    return ngx.shared.badsector_counters
end

--- Attack mode acik mi? (cache'li)
---@return boolean
function _M.is_on()
    local d = dict()
    if d then
        local cached = d:get(CACHE_KEY)
        if cached ~= nil then
            return cached == 1
        end
    end

    -- Cache miss: Redis'ten oku (worker basina ~5s'de bir)
    local on = false
    local red = redis.connect()
    if red then
        local v = red:get("bs:attack_mode")
        if v and v ~= ngx.null and tostring(v) == "1" then
            on = true
        end
        redis.keepalive(red)
    end

    if d then
        d:set(CACHE_KEY, on and 1 or 0, TTL)
    end
    return on
end

return _M
