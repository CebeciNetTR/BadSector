--[[
  BadSector Decision Executor

  Applies terminal decisions to the nginx request.
]]

local decision = require("badsector.decision")

local _M = {}

--- Apply a terminal decision to the current request.
---@param ctx table RequestContext
function _M.apply(ctx)
    local d = ctx.decision
    if not d then
        return
    end

    local action = d.action

    if action == "ALLOW" then
        -- Pipeline complete — reverse_proxy module or nginx location handles upstream
        return

    elseif action == "BLOCK" or action == "CUSTOM_RESPONSE" then
        ngx.header["X-BadSector-Action"] = "block"
        ngx.status = d.status or 403
        for k, v in pairs(d.headers or {}) do
            ngx.header[k] = v
        end
        ngx.say(d.body or "")
        return ngx.exit(d.status or 403)

    elseif action == "RETURN_444" then
        ngx.header["X-BadSector-Action"] = "block"
        return ngx.exit(444)

    elseif action == "REDIRECT" then
        return ngx.redirect(d.url, d.status or 302)

    elseif action == "RATE_LIMIT" then
        local retry = d.retry_after or 60
        ngx.header["Retry-After"] = tostring(retry)
        if d.limit then
            ngx.header["X-RateLimit-Limit"] = tostring(d.limit)
        end
        if d.remaining ~= nil then
            ngx.header["X-RateLimit-Remaining"] = tostring(d.remaining)
        end
        ngx.header["X-RateLimit-Reset"] = tostring(retry)
        ngx.status = 429
        ngx.say(d.body or "Too Many Requests")
        return ngx.exit(429)

    elseif action == "CHALLENGE" then
        _M.apply_challenge(ctx, d)

    elseif action == "CACHE" then
        -- Cache module sets ngx.ctx flags; actual cache logic in cache module
        ngx.ctx.badsector_cache = d
        return

    elseif action == "DELAY" then
        if d.ms and d.ms > 0 then
            ngx.sleep(d.ms / 1000)
        end
        return
    end
end

--- Apply challenge response based on challenge type.
---@param ctx table
---@param d table
function _M.apply_challenge(ctx, d)
    local challenge = require("badsector.challenge")
    challenge.issue(ctx, d.challenge_type, d.opts or {})
end

return _M
