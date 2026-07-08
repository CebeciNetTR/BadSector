--[[
  Inject GeoIP / ASN headers on requests forwarded to the origin backend.
  Disabled when site.settings.origin_geo_headers == false.

  Always sends X-BadSector-Edge and X-Geo-Status so PHP can confirm the request
  passed through BadSector even when country lookup fails.
]]

local geo_lookup = require("badsector.geo_lookup")

local _M = {}

local function set_var(name, value)
    ngx.var[name] = (value and value ~= "") and tostring(value) or ""
end

---@param ctx table RequestContext
---@param settings table|nil Site settings
function _M.apply(ctx, settings)
    settings = settings or {}

    -- Optional: send a different Host header to origin (e.g. subdomain site -> apex vhost).
    local origin_host = settings.origin_host
    if type(origin_host) == "string" then
        origin_host = origin_host:match("^%s*(.-)%s*$")
        if origin_host ~= "" then
            ngx.req.set_header("Host", origin_host)
        end
    end

    -- Always mark edge-proxied requests (even if geo headers disabled).
    set_var("badsector_edge", "1")
    ngx.req.set_header("X-BadSector-Edge", "1")

    if settings.origin_geo_headers == false then
        set_var("badsector_geo_status", "disabled")
        ngx.req.set_header("X-Geo-Status", "disabled")
        local rip = ctx.request and ctx.request.remote_addr
        if rip and rip ~= "" then
            set_var("badsector_client_ip", rip)
            ngx.req.set_header("X-Real-IP", rip)
        end
        return
    end

    local ip = ctx.request and ctx.request.remote_addr or ""
    set_var("badsector_client_ip", ip)
    if ip ~= "" then
        ngx.req.set_header("X-Real-IP", ip)
        ngx.req.set_header("X-BadSector-Client-IP", ip)
    end

    local geo = ctx.enrich and ctx.enrich.geo
    local geo_status = "unavailable"
    local geo_err

    if geo and geo.country and geo.country ~= "" then
        geo_status = "ok"
    else
        local cc = ctx:get_var("country")
        if cc and cc ~= "" then
            geo = { country = cc, source = "vars" }
            geo_status = "ok"
        else
            local looked, status, err = geo_lookup.lookup_country(ip)
            geo_err = err
            if looked then
                geo = looked
                geo_status = "ok"
            else
                geo_status = status or "unavailable"
            end
        end
    end

    set_var("badsector_geo_status", geo_status)
    ngx.req.set_header("X-Geo-Status", geo_status)
    if geo_err and geo_status ~= "ok" then
        ngx.req.set_header("X-Geo-Error", geo_err)
        set_var("badsector_geo_error", geo_err)
    end

    if geo and geo.country and geo.country ~= "" then
        local cc = geo.country:upper()
        set_var("badsector_country", cc)
        ngx.req.set_header("X-Country-Code", cc)
        ngx.req.set_header("X-Geo-Country", cc)
    end

    if geo and geo.city and geo.city ~= "" then
        set_var("badsector_geo_city", geo.city)
        ngx.req.set_header("X-Geo-City", geo.city)
    end

    local asn = ctx.enrich and ctx.enrich.asn
    if not (asn and asn.number) then
        local looked = geo_lookup.lookup_asn(ip)
        if looked and looked.number then
            asn = looked
        end
    end

    if asn and asn.number then
        local asn_str = tostring(asn.number)
        set_var("badsector_geo_asn", asn_str)
        ngx.req.set_header("X-Geo-ASN", asn_str)
        if asn.org and asn.org ~= "" and asn.org ~= "unknown" then
            set_var("badsector_geo_asn_org", asn.org)
            ngx.req.set_header("X-Geo-ASN-Org", asn.org)
        end
    end
end

return _M
