local decision = require("badsector.decision")
local geoip_db = require("badsector.geoip_db")

local M = { name = "asn", version = "1.0.0" }

local cfg = {
    enabled = true,
    database_path = "/etc/badsector/geoip/GeoLite2-ASN.mmdb",
    block_asns = {},
    allow_asns = {},
    allow_only = false,
    ip_map = {},
    fail_open = true,
}

local asn_db = nil

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.database_path = config.database_path or cfg.database_path
    cfg.block_asns = config.block_asns or {}
    cfg.allow_asns = config.allow_asns or {}
    cfg.allow_only = config.allow_only == true
    cfg.ip_map = config.ip_map or {}
    cfg.fail_open = config.fail_open ~= false

    geoip_db.close(asn_db)
    asn_db = nil

    if cfg.database_path then
        local db, err = geoip_db.open(cfg.database_path)
        if db then
            asn_db = db
        else
            ngx.log(ngx.NOTICE, "badsector asn: ", err or "asn db unavailable")
        end
    end
end

local function asn_in_list(number, list)
    if not number then
        return false
    end
    local n = tonumber(number)
    for _, entry in ipairs(list) do
        if tonumber(entry) == n then
            return true
        end
    end
    return false
end

local function lookup_mmdb(ip)
    if not asn_db then
        return nil
    end
    local res = geoip_db.lookup(asn_db, ip)
    if not res then
        return nil
    end
    return {
        number = res.autonomous_system_number,
        org = res.autonomous_system_organization,
        source = "mmdb",
    }
end

local function resolve_asn(ip)
    if cfg.ip_map[ip] then
        local mapped = cfg.ip_map[ip]
        mapped.source = mapped.source or "ip_map"
        return mapped
    end
    return lookup_mmdb(ip)
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end
    if not cfg.enabled then
        return decision.CONTINUE
    end

    local ip = ctx.request.remote_addr
    ctx:ensure("asn", function()
        return resolve_asn(ip) or { number = nil, org = "unknown", source = "none" }
    end)

    local asn = ctx.enrich.asn or {}
    local number = asn.number

    if number then
        ctx:set_var("asn", number)
        ctx:trace("asn", decision.CONTINUE, "ASN " .. tostring(number) .. " (" .. (asn.org or "?") .. ")", {
            source = asn.source,
        })
    else
        if not cfg.fail_open then
            ctx:trace("asn", decision.BLOCK, "ASN unknown")
            return decision.block(403, "Access denied")
        end
        ctx:trace("asn", decision.CONTINUE, "ASN unknown")
    end

    if number and cfg.allow_only and not asn_in_list(number, cfg.allow_asns) then
        ctx:trace("asn", decision.BLOCK, "ASN not on allow list: " .. tostring(number))
        return decision.block(403, "Access denied")
    end

    if number and asn_in_list(number, cfg.block_asns) then
        ctx:trace("asn", decision.BLOCK, "Blocked ASN: " .. tostring(number))
        return decision.block(403, "Access denied")
    end

    return decision.CONTINUE
end

return M
