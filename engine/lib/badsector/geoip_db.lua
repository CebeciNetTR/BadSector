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

local function build_profiles()
    local profiles = {}
    for path, name in pairs(path_profiles) do
        profiles[name] = path
    end
    return profiles
end

local function sync_init()
    local profiles = build_profiles()
    if next(profiles) == nil then
        return true
    end

    local m = mod()
    local ok, initted, err = pcall(m.init, profiles)
    if not ok then
        ngx.log(ngx.ERR, "badsector geoip_db init crash: ", initted)
        return false, initted
    end
    if not initted then
        ngx.log(ngx.ERR, "badsector geoip_db init: ", err or "unknown")
        return false, err or "init failed"
    end
    return true
end

--- Drop cached profile map (e.g. after MMDB files appear on disk).
function _M.reset()
    path_profiles = {}
    profile_counter = 0
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

    local m = mod()
    local profile = path_profiles[path]

    if profile and m.has_profile(profile) then
        return {
            profile = profile,
            _mod = m,
        }
    end

    if not profile then
        profile_counter = profile_counter + 1
        profile = "p" .. tostring(profile_counter)
        path_profiles[path] = profile
    end

    local ok, err = sync_init()
    if not ok then
        path_profiles[path] = nil
        return nil, err or "maxminddb init failed"
    end

    if not m.has_profile(profile) then
        path_profiles[path] = nil
        return nil, "profile not registered: " .. profile
    end

    return {
        profile = profile,
        _mod = m,
    }
end

--- Lookup IP in database.
---@param db table
---@param ip string
---@return table|nil
---@return string|nil err
function _M.lookup(db, ip)
    if not db or not ip or ip == "" then
        return nil, "missing db or ip"
    end

    local res, err = db._mod.lookup(ip, nil, db.profile)
    if not res then
        return nil, err or "not found"
    end
    return res
end

--- Close database handle if supported.
---@param db table|nil
function _M.close(_db)
    -- profiles stay registered for worker lifetime
end

return _M
