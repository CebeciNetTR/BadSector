local geo_lookup = require("badsector.geo_lookup")
local decision = require("badsector.decision")
local M = {
    name = "geoip",
    version = "1.1.0",
}

local cfg = {
    database_path = "/etc/badsector/geoip/GeoLite2-Country.mmdb",
    fail_open = true,
    block_countries = {},
    allow_countries = {},
    allow_only = false,
    use_header_fallback = true,
    -- block (403) | drop (444 silent) | challenge (JS PoW)
    deny_action = "block",
}

local country_db_ok = false

local function normalize_deny_action(v)
    if v == "drop" or v == "challenge" or v == "block" then
        return v
    end
    return "block"
end

function M.reload(config)
    config = config or {}
    cfg.database_path = config.database_path or cfg.database_path
    cfg.fail_open = config.fail_open ~= false
    cfg.block_countries = config.block_countries or {}
    cfg.allow_countries = config.allow_countries or {}
    cfg.allow_only = config.allow_only == true
    cfg.use_header_fallback = config.use_header_fallback ~= false
    cfg.deny_action = normalize_deny_action(config.deny_action)

    country_db_ok = false
    local _, status, err = geo_lookup.lookup_country("8.8.8.8", cfg.database_path)
    if status == "db_missing" then
        ngx.log(ngx.WARN, "badsector geoip: ", err or "country db unavailable")
    elseif status == "ok" then
        country_db_ok = true
    end
end

function M.init(config)
    M.reload(config)
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
    if not country_db_ok then
        local _, status, err = geo_lookup.lookup_country(ip, cfg.database_path)
        if status == "db_missing" then
            return nil, err or "database not loaded"
        end
    end
    local geo, status, err = geo_lookup.lookup_country(ip, cfg.database_path)
    if geo then
        return geo
    end
    return nil, err or status or "lookup failed"
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

--- Apply configured deny_action for blocked / not-allowed countries.
local function deny(ctx, reason)
    local action = cfg.deny_action or "block"
    if action == "drop" then
        ctx:trace("geoip", decision.RETURN_444, reason)
        return decision.RETURN_444
    end
    if action == "challenge" then
        local pow = require("badsector.pow")
        local diff = pow.difficulty({})
        local token = pow.make_challenge(ctx.request.remote_addr, diff)
        ctx:trace("geoip", decision.CHALLENGE, reason, { deny_action = "challenge", difficulty = diff })
        return decision.challenge("js", {
            token = token,
            difficulty = diff,
            pow_cookie = "bs_pow",
            template = "", -- site/global resolve in challenge.lua
        })
    end
    ctx:trace("geoip", decision.BLOCK, reason, { deny_action = "block" })
    return decision.block(403, "Access denied")
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
            return deny(ctx, "Country unknown")
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
        return deny(ctx, "Country not allowed: " .. geo.country)
    end

    if country_in_list(geo.country, cfg.block_countries) then
        return deny(ctx, "Country blocked: " .. geo.country)
    end

    return decision.CONTINUE
end

return M
