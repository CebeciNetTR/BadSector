#!/usr/local/openresty/bin/resty
--[[
  Tek IP → ASN numarasi (watcher attack-kernel icin).
  Ayni MMDB: BADSECTOR_ASN_MMDB / GeoLite2-ASN.mmdb (engine ile paylasilan volume).
]]
if not arg[1] or arg[1] == "" then
    os.exit(1)
end

package.path = "/usr/local/openresty/badsector/lib/?.lua;" .. package.path

local geo = require("badsector.geo_lookup")
local path = os.getenv("BADSECTOR_ASN_MMDB") or "/etc/badsector/geoip/GeoLite2-ASN.mmdb"
local ar, st = geo.lookup_asn(arg[1], path)
if ar and st == "ok" and ar.number then
    print(tostring(ar.number))
end
