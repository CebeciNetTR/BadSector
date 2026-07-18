--[[
  Client IP resolution.

  BADSECTOR_CLOUDFLARE=false (varsayilan, edge = BadSector):
    X-Real-IP (HAProxy %[src]) → remote_addr
    CF-Connecting-IP / XFF okunmaz (spoof kapali).

  BADSECTOR_CLOUDFLARE=true (trafik Cloudflare uzerinden):
    CF-Connecting-IP → X-Real-IP → remote_addr

  Ileri seviye (nadiren): BADSECTOR_TRUST_X_FORWARDED_FOR=true
]]

local _M = {}

local function env_on(name)
    local v = (os.getenv(name) or ""):lower()
    return v == "1" or v == "true" or v == "yes" or v == "on"
end

-- Ana anahtar (+ eski env adi geriye uyumluluk)
local CLOUDFLARE = env_on("BADSECTOR_CLOUDFLARE") or env_on("BADSECTOR_TRUST_CF_CONNECTING_IP")
local TRUST_XFF = env_on("BADSECTOR_TRUST_X_FORWARDED_FOR")

local function trim(s)
    if not s or type(s) ~= "string" then
        return ""
    end
    return (s:match("^%s*(.-)%s*$")) or ""
end

local function header_string(value)
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        value = value[1]
    end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    local s = trim(value)
    if s == "" then
        return nil
    end
    return s
end

local function header_value(headers, ...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        local v = header_string(headers[name])
        if v then
            return v
        end
    end
    return nil
end

local function is_private(ip)
    if not ip or ip == "" then
        return true
    end
    if ip:find(":") then
        return ip:match("^fe80:") or ip:match("^fc") or ip:match("^fd") or ip == "::1"
    end
    local o1, o2 = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not o1 then
        return false
    end
    o1, o2 = tonumber(o1), tonumber(o2)
    if o1 == 10 then return true end
    if o1 == 127 then return true end
    if o1 == 192 and o2 == 168 then return true end
    if o1 == 172 and o2 >= 16 and o2 <= 31 then return true end
    return false
end

local function first_ip_from_xff(xff)
    local first, first_public
    for part in xff:gmatch("[^,]+") do
        local ip = trim(part)
        if ip ~= "" then
            first = first or ip
            if not is_private(ip) then
                first_public = ip
                break
            end
        end
    end
    return first_public or first
end

---@return string
function _M.from_request()
    local headers = ngx.req.get_headers()

    if CLOUDFLARE then
        local cf_ip = header_value(headers, "CF-Connecting-IP", "cf-connecting-ip")
        if cf_ip then
            return cf_ip
        end
    end

    if TRUST_XFF then
        local xff = header_value(headers, "X-Forwarded-For", "x-forwarded-for")
        if xff then
            local ip = first_ip_from_xff(xff)
            if ip then
                return ip
            end
        end
    end

    local real = header_value(headers, "X-Real-IP", "x-real-ip")
    if real then
        return real
    end

    return ngx.var.remote_addr or ""
end

return _M
