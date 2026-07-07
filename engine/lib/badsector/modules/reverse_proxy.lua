local decision = require("badsector.decision")

local M = {
    name = "reverse_proxy",
    version = "1.0.0",
}

local default_backend = "http://backend"

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    if config.backend_url and config.backend_url ~= "" then
        default_backend = config.backend_url
    elseif config.upstream and config.upstream ~= "" then
        default_backend = "http://" .. config.upstream
    else
        default_backend = "http://backend"
    end
end

function M.run(ctx, config)
    config = config or {}
    local target = default_backend

    if config.backend_url and config.backend_url ~= "" then
        target = config.backend_url
    elseif config.upstream and config.upstream ~= "" then
        target = "http://" .. config.upstream
    end

    ngx.var.badsector_backend = target
    ngx.ctx.badsector_upstream = target

    ctx:trace("reverse_proxy", decision.ALLOW, "proxy to " .. target)
    return decision.ALLOW
end

return M
