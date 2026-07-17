--[[
  Global trusted IPs — ban / GeoIP challenge / pipeline filtrelerinden muaf.
  Yalnizca env: BADSECTOR_TRUSTED_IPS=1.2.3.4,5.6.7.8
  Bos ise kimse muaf degil (kodda sabit IP yok).
]]

local _M = {}

local set = nil

local function rebuild()
    set = {}
    local raw = os.getenv("BADSECTOR_TRUSTED_IPS") or ""
    for part in raw:gmatch("[^,]+") do
        local ip = part:match("^%s*(.-)%s*$")
        if ip and ip ~= "" then
            set[ip] = true
        end
    end
end

function _M.is(ip)
    if not set then
        rebuild()
    end
    if not ip or ip == "" then
        return false
    end
    return set[ip] == true
end

--- Env degisince worker restart gerekir.
function _M.reload()
    rebuild()
end

return _M
