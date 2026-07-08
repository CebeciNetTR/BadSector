local cjson = require("cjson.safe")
local pipeline = require("badsector.pipeline")

local _M = {}

local sites = {}
local sites_by_host = {}
local VERSION_KEY = "sites_version"
local _local_version = 0

local function shared_dict()
    return ngx.shared.badsector_config
end

function _M.runtime_path()
    return os.getenv("BADSECTOR_RUNTIME") or "/etc/badsector/runtime"
end

--- Load site configurations from runtime directory.
---@param runtime_path string|nil
function _M.load(runtime_path)
    runtime_path = runtime_path or _M.runtime_path()

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
            local key = host and string.lower(host) or ""
            if key ~= "" then
                sites_by_host[key] = site
            end
        end
    end
end

--- After init_worker load, align this worker with the shared config generation.
function _M.mark_loaded()
    local dict = shared_dict()
    if not dict then
        return
    end
    local ver = dict:get(VERSION_KEY)
    if not ver then
        ver = 1
        dict:set(VERSION_KEY, ver)
    end
    _local_version = ver
end

local function bump_version()
    local dict = shared_dict()
    if not dict then
        return ngx.time()
    end
    local new_ver, err = dict:incr(VERSION_KEY, 1, 0)
    if not new_ver then
        ngx.log(ngx.WARN, "badsector: config version bump failed: ", err)
        new_ver = ngx.time()
        dict:set(VERSION_KEY, new_ver)
    end
    return new_ver
end

--- Hot reload is triggered on one worker; others pick up via shared dict version.
function _M.sync_if_needed()
    local dict = shared_dict()
    if not dict then
        return
    end
    local global_ver = dict:get(VERSION_KEY) or 0
    if global_ver == _local_version then
        return
    end
    _M.load(_M.runtime_path())
    pipeline.reload(sites)
    _local_version = global_ver
end

--- Resolve site by Host header.
---@param host string
---@return table|nil
function _M.resolve(host)
    if not host or host == "" then
        return nil
    end
    return sites_by_host[string.lower(host)]
end

--- Get all loaded sites.
---@return table
function _M.all()
    return sites
end

--- Reload configuration (hot reload entry point).
---@param runtime_path string|nil
function _M.reload(runtime_path)
    runtime_path = runtime_path or _M.runtime_path()
    _M.load(runtime_path)
    pipeline.reload(sites)
    _local_version = bump_version()
end

return _M
