#!/usr/local/openresty/bin/resty
--[[
  Batch country + ASN lookup — BadSector geo_lookup (Country + ASN MMDB).
  stdin: IP satiri; stdout: IP<TAB>CC<TAB>ASN<TAB>ORG
]]

package.path = "/usr/local/openresty/badsector/lib/?.lua;" .. package.path

local geo = require("badsector.geo_lookup")
local country_path = os.getenv("BADSECTOR_GEOIP_COUNTRY_MMDB")
    or "/etc/badsector/geoip/GeoLite2-Country.mmdb"
local asn_path = os.getenv("BADSECTOR_GEOIP_ASN_MMDB")
    or "/etc/badsector/geoip/GeoLite2-ASN.mmdb"

for line in io.stdin:lines() do
    local ip = line:match("^(%S+)")
    if ip and ip:match("^%d+%.%d+%.%d+%.%d+$") then
        local cc = "??"
        local cr = geo.lookup_country(ip, country_path)
        if cr and cr.country then
            cc = string.upper(tostring(cr.country))
        end

        local asn_num = ""
        local asn_org = ""
        local ar, st = geo.lookup_asn(ip, asn_path)
        if ar and st == "ok" then
            if ar.number then asn_num = tostring(ar.number) end
            if ar.org then asn_org = tostring(ar.org) end
        end

        -- org icinde tab yok
        asn_org = asn_org:gsub("\t", " ")
        print(ip .. "\t" .. cc .. "\t" .. asn_num .. "\t" .. asn_org)
    end
end
