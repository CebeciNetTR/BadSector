local decision = require("badsector.decision")

local M = {
    name = "reverse_proxy",
    version = "1.0.0",
}

local default_backend = "http://backend:80"

local function normalize_backend(url)
    if type(url) ~= "string" then
        return nil
    end
    url = url:match("^%s*(.-)%s*$")
    if url == "" then
        return nil
    end
    if not url:find("://") then
        url = "http://" .. url
    end
    return url
end

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    local url = normalize_backend(config.backend_url)
    if url then
        default_backend = url
    elseif config.upstream and config.upstream ~= "" then
        default_backend = "http://" .. config.upstream
    else
        default_backend = "http://backend:80"
    end
end

function M.run(ctx, config)
    config = config or {}
    local target = normalize_backend(config.backend_url)

    if not target and config.upstream and config.upstream ~= "" then
        target = "http://" .. config.upstream
    end

    if not target then
        target = default_backend
    end

    ngx.var.badsector_backend = target
    ngx.ctx.badsector_upstream = target

    ctx:trace("reverse_proxy", decision.CONTINUE, "proxy to " .. target)
    return decision.CONTINUE
end

return M
