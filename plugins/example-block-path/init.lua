local decision = require("badsector.decision")

local blocked_prefixes = {}

local M = {
    name = "example-block-path",
    version = "1.0.0",
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    blocked_prefixes = (config or {}).prefixes or { "/.env", "/.git" }
end

function M.run(ctx)
    local path = ctx.request.path
    for _, prefix in ipairs(blocked_prefixes) do
        if path:sub(1, #prefix) == prefix then
            ctx:trace(M.name, decision.RETURN_444, "blocked path prefix: " .. prefix)
            return decision.RETURN_444
        end
    end
    return decision.CONTINUE
end

return M
