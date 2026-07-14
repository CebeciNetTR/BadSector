--[[
  BadSector Proof-of-Work challenge — stateless (Redis'siz) imzali token'lar.

  Iki token turu vardir, ikisi de HMAC-SHA256 ile imzalanir ve sunucuda HICBIR
  state tutulmaz (dogrulama yalnizca imza + zaman + PoW teyidi):

    1) Challenge token:  "ts.d.salt.sig"
         sig = HMAC(secret, "chal|" .. ip .. "|" .. "ts.d.salt")
       Istemci, sha256_hex(token .. ":" .. nonce) degeri "d" adet basta sifir
       (hex nibble) icerecek bir nonce (solution) bulur. d imzali oldugu icin
       istemci zorlugu dusuremez.

    2) Pass token (cozuldukten sonra verilen "gecis" cookie'si):  "exp.sig"
         sig = HMAC(secret, "pass|" .. ip .. "|" .. ua_fp .. "|" .. exp)
       Sonraki isteklerde tek bir HMAC ile (~us) dogrulanir -> hizli yol.

  Zorluk otomatik: attack mode ACIKKEN daha yuksek difficulty uygulanir.
]]

local crypto = require("badsector.crypto")
local attack_mode = require("badsector.attack_mode")

local _M = {}

local SECRET = os.getenv("BADSECTOR_CHALLENGE_SECRET")
if not SECRET or SECRET == "" then
    SECRET = "badsector-dev-challenge-secret-change-me"
end

local CHAL_TTL         = tonumber(os.getenv("BADSECTOR_POW_CHAL_TTL")) or 300      -- challenge gecerlilik (s)
local DEFAULT_DIFF     = tonumber(os.getenv("BADSECTOR_POW_DIFFICULTY")) or 4      -- normal (hex nibble)
local ATTACK_DIFF      = tonumber(os.getenv("BADSECTOR_POW_DIFFICULTY_ATTACK")) or 5
local DEFAULT_PASS_TTL = tonumber(os.getenv("BADSECTOR_POW_PASS_TTL")) or 3600     -- pass cookie omru (s)

_M.DEFAULT_PASS_TTL = DEFAULT_PASS_TTL

--- Tarayici parmak izi (UA -> kisa hash). Pass'i UA'ya baglar.
local function ua_fp(ua)
    return crypto.sha256_hex(ua or ""):sub(1, 16)
end

--- Etkin zorluk: config override + attack mode farkindaligi.
---@param opts table|nil { difficulty, difficulty_attack }
---@return integer
function _M.difficulty(opts)
    opts = opts or {}
    local base = tonumber(opts.difficulty) or DEFAULT_DIFF
    if attack_mode.is_on() then
        local a = tonumber(opts.difficulty_attack) or ATTACK_DIFF
        if a > base then
            return a
        end
    end
    return base
end

-- ---- Challenge token ----

local function chal_sig(ip, body)
    return crypto.hmac_sha256_hex(SECRET, "chal|" .. (ip or "") .. "|" .. body)
end

--- Yeni bir challenge token uretir (ts.d.salt.sig).
---@param ip string
---@param difficulty integer
---@return string token
---@return integer difficulty
function _M.make_challenge(ip, difficulty)
    local ts = ngx.time()
    local salt = crypto.rand_hex(8)
    local body = ts .. "." .. difficulty .. "." .. salt
    return body .. "." .. chal_sig(ip, body), difficulty
end

--- Istemcinin gonderdigi "token:solution" degerini dogrular.
---@param ip string
---@param value string  bs_pow cookie degeri ("ts.d.salt.sig:solution")
---@return boolean ok
---@return string|nil err
function _M.verify_solution(ip, value)
    if type(value) ~= "string" then
        return false, "empty"
    end
    local colon = value:find(":", 1, true)
    if not colon then
        return false, "format"
    end
    local token = value:sub(1, colon - 1)
    local solution = value:sub(colon + 1)
    if solution == "" or #solution > 64 then
        return false, "solution"
    end

    local ts, d, salt, sig = token:match("^(%d+)%.(%d+)%.(%x+)%.(%x+)$")
    if not ts then
        return false, "token"
    end

    -- 1) Imza (ip + body'ye bagli, kurcalamaya dayanikli)
    local body = ts .. "." .. d .. "." .. salt
    if not crypto.const_eq(chal_sig(ip, body), sig) then
        return false, "sig"
    end

    -- 2) Zaman penceresi (eski/gelecek token reddi)
    local tsn = tonumber(ts)
    local now = ngx.time()
    if not tsn or (now - tsn) > CHAL_TTL or (tsn - now) > 60 then
        return false, "expired"
    end

    -- 3) PoW: sha256_hex(token .. ":" .. solution) basta d adet sifir
    local diff = tonumber(d)
    if not diff or diff < 1 or diff > 12 then
        return false, "difficulty"
    end
    local h = crypto.sha256_hex(token .. ":" .. solution)
    if h:sub(1, diff) ~= string.rep("0", diff) then
        return false, "pow"
    end

    return true
end

-- ---- Pass token ----

local function pass_sig(ip, uafp, exp)
    return crypto.hmac_sha256_hex(SECRET, "pass|" .. (ip or "") .. "|" .. (uafp or "") .. "|" .. exp)
end

--- Cozulmus istemciye verilecek pass token'i uretir (exp.sig).
---@param ip string
---@param ua string
---@param ttl integer|nil
---@return string value
---@return integer ttl
function _M.make_pass(ip, ua, ttl)
    ttl = tonumber(ttl) or DEFAULT_PASS_TTL
    local exp = ngx.time() + ttl
    return exp .. "." .. pass_sig(ip, ua_fp(ua), exp), ttl
end

--- Pass token'i dogrular (hizli yol: 1 HMAC).
---@param ip string
---@param ua string
---@param value string
---@return boolean
function _M.verify_pass(ip, ua, value)
    if type(value) ~= "string" then
        return false
    end
    local exp, sig = value:match("^(%d+)%.(%x+)$")
    if not exp then
        return false
    end
    if ngx.time() > tonumber(exp) then
        return false
    end
    return crypto.const_eq(pass_sig(ip, ua_fp(ua), exp), sig)
end

return _M
