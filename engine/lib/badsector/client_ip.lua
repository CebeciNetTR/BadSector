--[[
  Resolve the original client IP when BadSector sits behind HAProxy or another proxy.
]]

local _M = {}

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
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

--- Leftmost public IP in X-Forwarded-For, else first entry, else X-Real-IP, else remote_addr.
---@return string
function _M.from_request()
    local headers = ngx.req.get_headers()
    local xff = headers["X-Forwarded-For"] or headers["x-forwarded-for"]
    if xff and xff ~= "" then
        local first, first_public
        for part in xff:gmatch("[^,]+") do
            local ip = trim(part)
            if ip and ip ~= "" then
                first = first or ip
                if not is_private(ip) then
                    first_public = ip
                    break
                end
            end
        end
        if first_public then
            return first_public
        end
        if first then
            return first
        end
    end

    local real = headers["X-Real-IP"] or headers["x-real-ip"]
    if real and real ~= "" then
        real = trim(real)
        if real ~= "" then
            return real
        end
    end

    return ngx.var.remote_addr or ""
end

return _M
