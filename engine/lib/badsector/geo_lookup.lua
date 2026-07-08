--[[
  Shared MaxMind country / ASN lookup for pipeline modules and origin headers.
]]

local geoip_db = require("badsector.geoip_db")

local _M = {}

local DEFAULT_COUNTRY = "/etc/badsector/geoip/GeoLite2-Country.mmdb"
local DEFAULT_ASN = "/etc/badsector/geoip/GeoLite2-ASN.mmdb"

local country_dbs = {}
local asn_dbs = {}

local function country_code(res)
    if not res then
        return nil
    end
    local cc = res.country and res.country.iso_code
    if not cc and res.registered_country then
        cc = res.registered_country.iso_code
    end
    return cc
end

function _M.reset()
    country_dbs = {}
    asn_dbs = {}
    geoip_db.reset()
end

---@param ip string
---@param path string|nil
---@return table|nil geo
---@return string status ok|unavailable|db_missing
---@return string|nil err
function _M.lookup_country(ip, path)
    path = path or DEFAULT_COUNTRY
    if not ip or ip == "" then
        return nil, "unavailable", "empty ip"
    end

    if not country_dbs[path] then
        local db, err = geoip_db.open(path)
        if not db then
            return nil, "db_missing", err
        end
        country_dbs[path] = db
    end

    local res, err = geoip_db.lookup(country_dbs[path], ip)
    if not res then
        return nil, "unavailable", err
    end

    local cc = country_code(res)
    if not cc then
        return nil, "unavailable", "no country in record"
    end

    return {
        country = cc,
        city = res.city and res.city.names and res.city.names.en,
        latitude = res.location and res.location.latitude,
        longitude = res.location and res.location.longitude,
        source = "mmdb",
    }, "ok"
end

---@param ip string
---@param path string|nil
---@return table|nil asn
---@return string status
---@return string|nil err
function _M.lookup_asn(ip, path)
    path = path or DEFAULT_ASN
    if not ip or ip == "" then
        return nil, "unavailable", "empty ip"
    end

    if not asn_dbs[path] then
        local db, err = geoip_db.open(path)
        if not db then
            return nil, "db_missing", err
        end
        asn_dbs[path] = db
    end

    local res, err = geoip_db.lookup(asn_dbs[path], ip)
    if not res then
        return nil, "unavailable", err
    end

    return {
        number = res.autonomous_system_number,
        org = res.autonomous_system_organization,
        source = "mmdb",
    }, "ok"
end

return _M
