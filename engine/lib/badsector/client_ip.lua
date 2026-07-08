--[[
  Resolve the original client IP when BadSector sits behind HAProxy, Cloudflare, etc.
  Header values may be a string or a table (duplicate headers in OpenResty).
]]

local _M = {}

local function trim(s)
    if not s or type(s) ~= "string" then
        return ""
    end
    return (s:match("^%s*(.-)%s*$")) or ""
end

--- Normalize ngx header value to a single string.
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

--- Client IP: CF-Connecting-IP (Cloudflare) → X-Forwarded-For → X-Real-IP → remote_addr.
---@return string
function _M.from_request()
    local headers = ngx.req.get_headers()

    -- Cloudflare (orange cloud) sends the visitor IP here.
    local cf_ip = header_value(headers, "CF-Connecting-IP", "cf-connecting-ip")
    if cf_ip then
        return cf_ip
    end

    local xff = header_value(headers, "X-Forwarded-For", "x-forwarded-for")
    if xff then
        local ip = first_ip_from_xff(xff)
        if ip then
            return ip
        end
    end

    local real = header_value(headers, "X-Real-IP", "x-real-ip")
    if real then
        return real
    end

    return ngx.var.remote_addr or ""
end

return _M
