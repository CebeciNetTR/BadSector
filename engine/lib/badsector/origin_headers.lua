--[[
  Inject GeoIP / ASN headers on requests forwarded to the origin backend.
  Disabled when site.settings.origin_geo_headers == false.
]]

local _M = {}

---@param ctx table RequestContext
---@param settings table|nil Site settings
function _M.apply(ctx, settings)
    settings = settings or {}
    if settings.origin_geo_headers == false then
        return
    end

    local geo = ctx.enrich and ctx.enrich.geo
    if geo and geo.country and geo.country ~= "" then
        local cc = geo.country:upper()
        ngx.req.set_header("X-Country-Code", cc)
        ngx.req.set_header("X-Geo-Country", cc)
        if geo.city and geo.city ~= "" then
            ngx.req.set_header("X-Geo-City", geo.city)
        end
    end

    local asn = ctx.enrich and ctx.enrich.asn
    if asn and asn.number then
        ngx.req.set_header("X-Geo-ASN", tostring(asn.number))
        if asn.org and asn.org ~= "" and asn.org ~= "unknown" then
            ngx.req.set_header("X-Geo-ASN-Org", asn.org)
        end
    end
end

return _M
