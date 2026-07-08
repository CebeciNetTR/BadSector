local decision = require("badsector.decision")
local util = require("badsector.util")
local geoip_db = require("badsector.geoip_db")

local M = {
    name = "geoip",
    version = "1.0.0",
}

local cfg = {
    database_path = "/etc/badsector/geoip/GeoLite2-Country.mmdb",
    fail_open = true,
    block_countries = {},
    allow_countries = {},
    allow_only = false,
    use_header_fallback = true,
}

local country_db = nil

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.database_path = config.database_path or cfg.database_path
    cfg.fail_open = config.fail_open ~= false
    cfg.block_countries = config.block_countries or {}
    cfg.allow_countries = config.allow_countries or {}
    cfg.allow_only = config.allow_only == true
    cfg.use_header_fallback = config.use_header_fallback ~= false

    geoip_db.close(country_db)
    country_db = nil

    local db, err = geoip_db.open(cfg.database_path)
    if db then
        country_db = db
    else
        ngx.log(ngx.WARN, "badsector geoip: ", err or "country db unavailable")
    end
end

local function country_in_list(code, list)
    if not code then
        return false
    end
    code = code:upper()
    for _, c in ipairs(list) do
        if type(c) == "string" and c:upper() == code then
            return true
        end
    end
    return false
end

local function lookup_mmdb(ip)
    if not country_db then
        return nil, "database not loaded"
    end
    local res, err = geoip_db.lookup(country_db, ip)
    if not res then
        return nil, err or "lookup failed"
    end
    local cc = res.country and res.country.iso_code
    if not cc and res.registered_country then
        cc = res.registered_country.iso_code
    end
    if not cc then
        return nil, "no country in record"
    end
    return {
        country = cc,
        city = res.city and res.city.names and res.city.names.en,
        latitude = res.location and res.location.latitude,
        longitude = res.location and res.location.longitude,
        source = "mmdb",
    }
end

local function header_fallback(headers)
    if not cfg.use_header_fallback then
        return nil
    end
    headers = headers or {}
    local cc = headers["CF-IPCountry"] or headers["X-Country-Code"] or headers["X-Geo-Country"]
    if cc and cc ~= "" and cc ~= "XX" then
        return { country = cc:upper(), source = "header" }
    end
    return nil
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end

    local lookup_err
    ctx:ensure("geo", function()
        local geo, err = lookup_mmdb(ctx.request.remote_addr)
        if geo then
            return geo
        end
        lookup_err = err
        return header_fallback(ctx.request.headers)
    end)

    local geo = ctx.enrich.geo

    if not geo or not geo.country then
        if not cfg.fail_open then
            ctx:trace("geoip", decision.BLOCK, "Country unknown")
            return decision.block(403, "Access denied")
        end
        local detail = "Geo lookup unavailable"
        if lookup_err then
            detail = detail .. ": " .. lookup_err
        end
        if ctx.request.remote_addr == "127.0.0.1" or ctx.request.remote_addr == "::1" then
            detail = detail .. " (localhost has no GeoIP; test from browser or set X-Forwarded-For)"
        end
        ctx:trace("geoip", decision.CONTINUE, detail)
        return decision.CONTINUE
    end

    geo.country = geo.country:upper()
    ctx:set_var("country", geo.country)
    ctx:trace("geoip", decision.CONTINUE, "Country: " .. geo.country, { source = geo.source })

    if cfg.allow_only and not country_in_list(geo.country, cfg.allow_countries) then
        ctx:trace("geoip", decision.BLOCK, "Country not allowed: " .. geo.country)
        return decision.block(403, "Access denied")
    end

    if country_in_list(geo.country, cfg.block_countries) then
        ctx:trace("geoip", decision.BLOCK, "Country blocked: " .. geo.country)
        return decision.block(403, "Access denied")
    end

    return decision.CONTINUE
end

return M
