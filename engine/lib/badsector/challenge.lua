--[[
  Challenge issuer — JS, cookie, and captcha challenges.
]]

local util = require("badsector.util")

local _M = {}

--- Issue a challenge to the client.
---@param ctx table RequestContext
---@param challenge_type string
---@param opts table
function _M.issue(ctx, challenge_type, opts)
    opts = opts or {}

    if challenge_type == "js" then
        local cookie_name = opts.cookie_name or "bs_js_ok"
        local ttl = tonumber(opts.cookie_ttl) or 3600
        ngx.header["Content-Type"] = "text/html; charset=utf-8"
        ngx.header["Cache-Control"] = "no-store"
        ngx.status = 503
        ngx.say(_M.js_challenge_page(cookie_name, ttl))
        return ngx.exit(503)

    elseif challenge_type == "cookie" then
        local cookie_name = opts.cookie_name or "bs_verified"
        local ttl = tonumber(opts.cookie_ttl) or 86400
        local token = util.random_token(16)
        ngx.header["Set-Cookie"] = cookie_name .. "=" .. token .. "; Path=/; Max-Age=" .. ttl .. "; HttpOnly; SameSite=Lax"
        ngx.header["Cache-Control"] = "no-store"
        ngx.status = 403
        ngx.say("Verification required. Reload to continue.")
        return ngx.exit(403)

    elseif challenge_type == "captcha" then
        ngx.status = 403
        ngx.say("Captcha challenge — configure provider in site settings")
        return ngx.exit(403)
    end

    ngx.status = 403
    return ngx.exit(403)
end

--- Minimal JS challenge page template.
---@param cookie_name string
---@param ttl number
---@return string
function _M.js_challenge_page(cookie_name, ttl)
    return string.format([[<!DOCTYPE html>
<html><head><title>Checking your browser</title></head>
<body><p>Checking your browser before accessing this site...</p>
<script>
(function(){
  document.cookie="%s=1;path=/;max-age=%d;SameSite=Lax";
  location.reload();
})();
</script></body></html>]], cookie_name, ttl)
end

return _M
