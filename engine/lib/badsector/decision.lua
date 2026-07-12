--[[
  BadSector Decision Types

  Every module returns a Decision object.
  Terminal decisions halt pipeline execution immediately.
]]

local _M = {}

-- Non-terminal
_M.CONTINUE = { action = "CONTINUE", terminal = false }

-- Terminal decisions
_M.ALLOW = { action = "ALLOW", terminal = true }
_M.RETURN_444 = { action = "RETURN_444", terminal = true }
_M.BLOCK = { action = "BLOCK", terminal = true }
_M.CHALLENGE = { action = "CHALLENGE", terminal = true }

--- Build a BLOCK decision with optional status, body, and headers.
---@param status number|nil HTTP status (default 403)
---@param body string|nil Response body
---@param headers table|nil Response headers
---@return table
function _M.block(status, body, headers)
    return {
        action = "BLOCK",
        terminal = true,
        status = status or 403,
        body = body,
        headers = headers or {},
    }
end

--- Build a REDIRECT decision.
---@param url string Target URL
---@param status number|nil HTTP status (default 302)
---@return table
function _M.redirect(url, status)
    return {
        action = "REDIRECT",
        terminal = true,
        status = status or 302,
        url = url,
    }
end

--- Build a CHALLENGE decision.
---@param challenge_type string "js" | "cookie" | "captcha"
---@param opts table|nil Challenge options
---@return table
function _M.challenge(challenge_type, opts)
    return {
        action = "CHALLENGE",
        terminal = true,
        challenge_type = challenge_type,
        opts = opts or {},
    }
end

--- Build a CACHE decision.
---@param ttl number Cache TTL in seconds
---@param key string|nil Cache key override
---@return table
function _M.cache(ttl, key)
    return {
        action = "CACHE",
        terminal = true,
        ttl = ttl,
        key = key,
    }
end

--- Build a CUSTOM_RESPONSE decision.
---@param status number HTTP status
---@param body string|nil Response body
---@param headers table|nil Response headers
---@return table
function _M.custom(status, body, headers)
    return {
        action = "CUSTOM_RESPONSE",
        terminal = true,
        status = status,
        body = body,
        headers = headers or {},
    }
end

--- Build a RATE_LIMIT decision.
---@param retry_after number|nil Seconds until retry
---@param meta table|nil Optional metadata (limit, remaining, count, rule_id)
---@return table
function _M.rate_limit(retry_after, meta)
    local d = {
        action = "RATE_LIMIT",
        terminal = true,
        status = 429,
        retry_after = retry_after or 60,
        body = "Too Many Requests",
    }
    if meta then
        for k, v in pairs(meta) do
            d[k] = v
        end
    end
    return d
end

--- Build a DELAY decision (non-terminal by default).
---@param ms number Delay in milliseconds
---@return table
function _M.delay(ms)
    return {
        action = "DELAY",
        terminal = false,
        ms = ms,
    }
end

--- Check if a decision terminates the pipeline.
---@param d table
---@return boolean
function _M.is_terminal(d)
    return d and d.terminal == true
end

return _M
