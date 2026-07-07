--[[
  Serve ACME HTTP-01 challenges from Redis (written by worker/API during cert issuance).
]]

local redis = require("badsector.redis")

local M = {}

function M.serve()
    local token = ngx.var.uri:match("/%.well%-known/acme%-challenge/(.+)$")
    if not token or token == "" then
        ngx.status = 404
        ngx.say("not found")
        return ngx.exit(404)
    end

    local red, err = redis.connect()
    if not red then
        ngx.log(ngx.ERR, "badsector acme: redis: ", err or "connect failed")
        ngx.status = 503
        ngx.say("challenge unavailable")
        return ngx.exit(503)
    end

    local key = "badsector:acme:" .. token
    local ok, value = red:get(key)
    redis.keepalive(red)

    if not ok or not value or value == ngx.null then
        ngx.status = 404
        ngx.say("challenge not found")
        return ngx.exit(404)
    end

    ngx.header["Content-Type"] = "text/plain"
    ngx.say(value)
    return ngx.exit(200)
end

function M.is_challenge_path(uri)
    return uri and uri:sub(1, 23) == "/.well-known/acme-challenge/"
end

return M
