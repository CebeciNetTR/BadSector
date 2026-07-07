--[[
  BadSector Engine Admin Endpoints

  Hot reload and health checks protected by admin token.
]]

local config = require("badsector.config")

local _M = {}

local function authorized()
    local token = os.getenv("BADSECTOR_ENGINE_ADMIN_TOKEN")
    if not token or token == "" then
        return true
    end

    local auth = ngx.var.http_authorization or ""
    if auth == "Bearer " .. token then
        return true
    end

    local header = ngx.var.http_x_badsector_admin_token
    return header == token
end

function _M.handle_reload()
    if not authorized() then
        ngx.status = 401
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"unauthorized"}')
        return ngx.exit(401)
    end

    local runtime = os.getenv("BADSECTOR_RUNTIME") or "/etc/badsector/runtime"
    config.reload(runtime)

    ngx.status = 200
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"status":"reloaded"}')
    return ngx.exit(200)
end

return _M
