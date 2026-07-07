local cjson = require("cjson.safe")
local pipeline = require("badsector.pipeline")

local _M = {}

local sites = {}
local sites_by_host = {}

--- Load site configurations from runtime directory.
---@param runtime_path string
function _M.load(runtime_path)
    runtime_path = runtime_path or "/etc/badsector/runtime"

    local f = io.open(runtime_path .. "/sites.json", "r")
    if not f then
        ngx.log(ngx.WARN, "badsector: no sites.json at ", runtime_path)
        return
    end

    local content = f:read("*a")
    f:close()

    local data, err = cjson.decode(content)
    if not data then
        ngx.log(ngx.ERR, "badsector: failed to parse sites.json: ", err)
        return
    end

    sites = data
    sites_by_host = {}

    for _, site in ipairs(sites) do
        for _, host in ipairs(site.hosts or {}) do
            sites_by_host[host] = site
        end
    end
end

--- Resolve site by Host header.
---@param host string
---@return table|nil
function _M.resolve(host)
    return sites_by_host[host]
end

--- Get all loaded sites.
---@return table
function _M.all()
    return sites
end

--- Reload configuration (hot reload entry point).
---@param runtime_path string|nil
function _M.reload(runtime_path)
    _M.load(runtime_path)
    pipeline.reload(sites)
end

return _M
