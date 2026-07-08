--[[
  Inject GeoIP / ASN headers on requests forwarded to the origin backend.
  Disabled when site.settings.origin_geo_headers == false.

  Sets ngx.var.badsector_* for nginx proxy_set_header (reliable with proxy_pass)
  and ngx.req.set_header as a fallback.
]]

local _M = {}

local function set_var(name, value)
    if value and value ~= "" then
        ngx.var[name] = tostring(value)
        return true
    end
    ngx.var[name] = ""
    return false
end

---@param ctx table RequestContext
---@param settings table|nil Site settings
function _M.apply(ctx, settings)
    settings = settings or {}
    if settings.origin_geo_headers == false then
        return
    end

    local geo = ctx.enrich and ctx.enrich.geo
    local cc = geo and geo.country or ctx:get_var("country")
    if cc and cc ~= "" then
        cc = cc:upper()
        set_var("badsector_country", cc)
        ngx.req.set_header("X-Country-Code", cc)
        ngx.req.set_header("X-Geo-Country", cc)
    end

    if geo and geo.city and geo.city ~= "" then
        set_var("badsector_geo_city", geo.city)
        ngx.req.set_header("X-Geo-City", geo.city)
    end

    local asn = ctx.enrich and ctx.enrich.asn
    if asn and asn.number then
        local asn_str = tostring(asn.number)
        set_var("badsector_geo_asn", asn_str)
        ngx.req.set_header("X-Geo-ASN", asn_str)
        if asn.org and asn.org ~= "" and asn.org ~= "unknown" then
            set_var("badsector_geo_asn_org", asn.org)
            ngx.req.set_header("X-Geo-ASN-Org", asn.org)
        end
    end

    local rip = ctx.request and ctx.request.remote_addr
    if rip and rip ~= "" then
        set_var("badsector_client_ip", rip)
        ngx.req.set_header("X-Real-IP", rip)
    end
end

return _M
