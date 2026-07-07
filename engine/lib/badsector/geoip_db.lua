--[[
  MaxMind DB helper — supports multiple MMDB files (Country + ASN).
  Uses anjia0532/lua-resty-maxminddb (OPM) profile API.
]]

local _M = {}

local mmdb_mod
local path_profiles = {}
local profile_counter = 0

local function mod()
    if not mmdb_mod then
        mmdb_mod = require("resty.maxminddb")
    end
    return mmdb_mod
end

local function sync_init()
    local profiles = {}
    for path, name in pairs(path_profiles) do
        profiles[name] = path
    end
    if next(profiles) == nil then
        return
    end
    local m = mod()
    local ok, err = pcall(m.init, profiles)
    if not ok then
        ngx.log(ngx.ERR, "badsector geoip_db init: ", err)
    end
end

--- Open an MMDB file (registers a named profile).
---@param path string
---@return table|nil db
---@return string|nil err
function _M.open(path)
    if not path or path == "" then
        return nil, "empty path"
    end

    local f = io.open(path, "r")
    if not f then
        return nil, "file not found: " .. path
    end
    f:close()

    if not path_profiles[path] then
        profile_counter = profile_counter + 1
        path_profiles[path] = "p" .. tostring(profile_counter)
        sync_init()
    end

    return {
        profile = path_profiles[path],
        _mod = mod(),
    }
end

--- Lookup IP in database.
---@param db table
---@param ip string
---@return table|nil
function _M.lookup(db, ip)
    if not db or not ip then
        return nil
    end

    local res, err = db._mod.lookup(ip, nil, db.profile)
    if not res and err then
        ngx.log(ngx.DEBUG, "badsector geoip_db lookup: ", err)
    end
    return res
end

--- Close database handle if supported.
---@param db table|nil
function _M.close(_db)
    -- profiles stay registered for worker lifetime
end

return _M
