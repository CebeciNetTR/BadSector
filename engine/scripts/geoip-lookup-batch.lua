#!/usr/local/openresty/bin/resty
--[[
  Batch country lookup — BadSector ile AYNI MMDB (geo_lookup / geoip modulu).
  stdin: bir IP satiri; stdout: IP<TAB>CC
]]

package.path = "/usr/local/openresty/badsector/lib/?.lua;" .. package.path

local geo = require("badsector.geo_lookup")
local path = os.getenv("BADSECTOR_GEOIP_COUNTRY_MMDB")
    or "/etc/badsector/geoip/GeoLite2-Country.mmdb"

for line in io.stdin:lines() do
    local ip = line:match("^(%S+)")
    if ip and ip:match("^%d+%.%d+%.%d+%.%d+$") then
        local res, status = geo.lookup_country(ip, path)
        local cc = "??"
        if res and res.country then
            cc = string.upper(tostring(res.country))
        elseif status == "db_missing" then
            io.stderr:write("geoip db missing: " .. path .. "\n")
            os.exit(1)
        end
        print(ip .. "\t" .. cc)
    end
end
