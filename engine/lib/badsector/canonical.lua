--[[
  Canonical hostname redirect — prefer apex or www at the edge (301 to HTTPS).
]]

local _M = {}

local function normalize_host(host)
    if not host or host == "" then
        return ""
    end
    return string.lower(host)
end

--- Split site hosts into apex and www variants.
---@param hosts table
---@return string|nil apex
---@return string|nil www
local function split_hosts(hosts)
    local apex, www
    for _, h in ipairs(hosts or {}) do
        local host = normalize_host(h)
        if host ~= "" then
            if host:sub(1, 4) == "www." then
                www = www or host
            else
                apex = apex or host
            end
        end
    end
    return apex, www
end

--- Enforce canonical host for this site. Redirects with 301 to https://canonical/...
---@param site table
---@param request_host string
---@return boolean redirected
function _M.enforce(site, request_host)
    local settings = site.settings or {}
    local mode = settings.canonical_host
    if mode ~= "apex" and mode ~= "www" then
        return false
    end

    local apex, www = split_hosts(site.hosts)
    local target

    if mode == "www" then
        target = www or (apex and ("www." .. apex) or nil)
    else
        target = apex
    end

    if not target or target == "" then
        return false
    end

    local current = normalize_host(request_host)
    if current == target then
        return false
    end

    -- Only redirect hosts declared on this site.
    local allowed = {}
    for _, h in ipairs(site.hosts or {}) do
        allowed[normalize_host(h)] = true
    end
    if not allowed[current] then
        return false
    end

    local uri = ngx.var.request_uri or "/"
    local url = "https://" .. target .. uri
    ngx.redirect(url, 301)
    return true
end

return _M
