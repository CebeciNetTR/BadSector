local decision = require("badsector.decision")

local M = {
    name = "access_lists",
    version = "1.0.0",
}

local allow_list = {}
local deny_list = {}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    allow_list = config.allow or {}
    deny_list = config.deny or {}
end

local function ip_matches(ip, list)
    for _, entry in ipairs(list) do
        if entry == ip then
            return true
        end
        -- CIDR matching delegated to util.ip_in_cidr in production
    end
    return false
end

function M.run(ctx)
    local ip = ctx.request.remote_addr

    if ip_matches(ip, deny_list) then
        ctx:trace("access_lists", decision.BLOCK, "IP on deny list")
        return decision.block(403, "Access denied")
    end

    if #allow_list > 0 and not ip_matches(ip, allow_list) then
        ctx:trace("access_lists", decision.BLOCK, "IP not on allow list")
        return decision.block(403, "Access denied")
    end

    return decision.CONTINUE
end

return M
