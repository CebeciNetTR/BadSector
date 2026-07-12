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
        ngx.status = 200
        ngx.say(_M.js_challenge_page(cookie_name, ttl))
        return ngx.exit(200)

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

--- Styled JS challenge page template.
---@param cookie_name string
---@param ttl number
---@return string
function _M.js_challenge_page(cookie_name, ttl)
    return string.format([[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Check | BadSector</title>
    <style>
        body {
            background-color: #0f172a;
            color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            overflow: hidden;
        }
        .container {
            text-align: center;
            max-width: 450px;
            padding: 40px;
            background: rgba(30, 41, 59, 0.7);
            border-radius: 16px;
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.4);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        h1 {
            font-size: 24px;
            margin-bottom: 12px;
            font-weight: 600;
        }
        p {
            color: #94a3b8;
            font-size: 15px;
            line-height: 1.5;
            margin-bottom: 24px;
        }
        .spinner {
            width: 48px;
            height: 48px;
            border: 4px solid rgba(255, 255, 255, 0.1);
            border-left-color: #3b82f6;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px auto;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>Checking your browser</h1>
        <p>Please wait a moment while we verify your connection. This process is automatic and helps prevent malicious traffic.</p>
    </div>
    <script>
        (function(){
            document.cookie="%s=1;path=/;max-age=%d;SameSite=Lax";
            setTimeout(function() {
                location.reload();
            }, 800);
        })();
    </script>
</body>
</html>]], cookie_name, ttl)
end

return _M
