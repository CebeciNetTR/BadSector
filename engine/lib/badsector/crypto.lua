--[[
  BadSector kripto yardimcilari — imzali challenge/pass token'lari icin.

  OpenResty ile gelen resty.sha256 (lua-resty-string) uzerine kuruludur; harici
  bagimlilik (lua-resty-openssl vb.) gerektirmez. HMAC-SHA256 standart ipad/opad
  yapisiyla elde edilir; padded key blocklari secret basina bir kez hesaplanir.

  Hepsi CPU-ici, tahsissiz-yakini islemlerdir (~mikrosaniye) — sicak yolda ucuz.
]]

local resty_sha256 = require("resty.sha256")
local resty_random = require("resty.random")
local str = require("resty.string")
local bit = require("bit")

local bxor = bit.bxor
local bor = bit.bor

local _M = {}

local function sha256_raw(s)
    local h = resty_sha256:new()
    h:update(s or "")
    return h:final()
end

--- SHA-256, hex string dondurur.
---@param s string
---@return string
function _M.sha256_hex(s)
    return str.to_hex(sha256_raw(s))
end

--- n bayt kriptografik rastgele -> hex.
---@param n integer|nil
---@return string
function _M.rand_hex(n)
    return str.to_hex(resty_random.bytes(n or 8))
end

-- Padded key blocklari secret basina cache'lenir (SHA-256 block boyutu 64).
local _key
local _ipad
local _opad

local function prepare_key(key)
    if _ipad and _key == key then
        return
    end
    _key = key
    local k = key or ""
    if #k > 64 then
        k = sha256_raw(k)
    end
    if #k < 64 then
        k = k .. string.rep("\0", 64 - #k)
    end
    local ip, op = {}, {}
    for i = 1, 64 do
        local b = k:byte(i)
        ip[i] = string.char(bxor(b, 0x36))
        op[i] = string.char(bxor(b, 0x5c))
    end
    _ipad = table.concat(ip)
    _opad = table.concat(op)
end

--- HMAC-SHA256(key, msg), hex string dondurur.
---@param key string
---@param msg string
---@return string
function _M.hmac_sha256_hex(key, msg)
    prepare_key(key)
    local inner = sha256_raw(_ipad .. (msg or ""))
    return str.to_hex(sha256_raw(_opad .. inner))
end

--- Sabit-zamanli string karsilastirma (timing oracle'a karsi).
---@param a string
---@param b string
---@return boolean
function _M.const_eq(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    if #a ~= #b then
        return false
    end
    local diff = 0
    for i = 1, #a do
        diff = bor(diff, bxor(a:byte(i), b:byte(i)))
    end
    return diff == 0
end

return _M
