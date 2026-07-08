--[[
  Canonical hostname redirect — prefer apex or www at the edge (301 to HTTPS).
  Only applies when the site lists both apex and matching www (e.g. example.com + www.example.com).
  Subdomains (trend.example.com) are never folded into apex redirect.
]]

local _M = {}

local function normalize_host(host)
    if not host or host == "" then
        return ""
    end
    return string.lower(host)
end

--- Find apex + www pair where www is exactly "www." .. apex and both are in hosts.
---@param hosts table
---@return string|nil apex
---@return string|nil www
local function apex_www_pair(hosts)
    local hostset = {}
    for _, h in ipairs(hosts or {}) do
        local n = normalize_host(h)
        if n ~= "" then
            hostset[n] = true
        end
    end

    for h, _ in pairs(hostset) do
        if h:sub(1, 4) ~= "www." then
            local candidate_www = "www." .. h
            if hostset[candidate_www] then
                return h, candidate_www
            end
        end
    end

    return nil, nil
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

    local apex, www = apex_www_pair(site.hosts)
    if not apex or not www then
        return false
    end

    local target
    if mode == "www" then
        target = www
    else
        target = apex
    end

    local current = normalize_host(request_host)
    if current == target then
        return false
    end

    -- Only redirect between the apex/www pair — never subdomains or extra hostnames.
    if current ~= apex and current ~= www then
        return false
    end

    local uri = ngx.var.request_uri or "/"
    local url = "https://" .. target .. uri
    ngx.redirect(url, 301)
    return true
end

return _M
