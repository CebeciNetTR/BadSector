local _M = {}

--- Generate a random hex token.
---@param bytes integer
---@return string
function _M.random_token(bytes)
    local resty_random = require("resty.random")
    local str = require("resty.string")
    return str.to_hex(resty_random.bytes(bytes or 16))
end

--- Check if IP matches CIDR (simplified; production uses lua-resty-iputils).
---@param ip string
---@param cidr string
---@return boolean
function _M.ip_in_cidr(ip, cidr)
    -- Placeholder: full implementation via resty.iputils
    return false
end

--- Safe table deep copy (one level).
---@param t table
---@return table
function _M.shallow_copy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

--- Match request path against glob patterns (/*, /api/*, exact).
---@param path string
---@param patterns table
---@return boolean
function _M.path_matches(path, patterns)
    if not patterns or #patterns == 0 then
        return true
    end

    for _, pattern in ipairs(patterns) do
        if pattern == "/*" or pattern == "*" then
            return true
        end
        if pattern:sub(-1) == "*" then
            local prefix = pattern:sub(1, -2)
            if path:sub(1, #prefix) == prefix then
                return true
            end
        elseif path == pattern then
            return true
        end
    end

    return false
end

--- Case-insensitive header lookup.
---@param headers table
---@param name string
---@return string|nil
function _M.header_get(headers, name)
    if not headers or not name then
        return nil
    end
    if headers[name] then
        return headers[name]
    end
    local lower = name:lower()
    for k, v in pairs(headers) do
        if type(k) == "string" and k:lower() == lower then
            return v
        end
    end
    return nil
end

return _M
