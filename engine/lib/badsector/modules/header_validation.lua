local decision = require("badsector.decision")
local util = require("badsector.util")

local M = { name = "header_validation", version = "1.0.0" }

local cfg = {
    enabled = true,
    required = {},
    forbidden = {},
    rules = {},
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.required = config.required or {}
    cfg.forbidden = config.forbidden or {}
    cfg.rules = config.rules or {}
end

local function check_header(headers, name, mode)
    local val = util.header_get(headers, name)
    if mode == "required" then
        return val and val ~= ""
    end
    if mode == "forbidden" then
        return val and val ~= ""
    end
    return false
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end
    if not cfg.enabled then
        return decision.CONTINUE
    end

    local headers = ctx.request.headers or {}

    for _, name in ipairs(cfg.required) do
        if not check_header(headers, name, "required") then
            ctx:trace("header_validation", decision.BLOCK, "Missing required header: " .. name)
            return decision.block(400, "Bad Request")
        end
    end

    for _, name in ipairs(cfg.forbidden) do
        if check_header(headers, name, "forbidden") then
            ctx:trace("header_validation", decision.BLOCK, "Forbidden header: " .. name)
            return decision.block(403, "Forbidden")
        end
    end

    for _, rule in ipairs(cfg.rules) do
        if rule.paths and #rule.paths > 0 then
            if not util.path_matches(ctx.request.path, rule.paths) then
                goto continue
            end
        end

        local header = rule.header or rule.name
        if not header then
            goto continue
        end

        if rule.required and not check_header(headers, header, "required") then
            ctx:trace("header_validation", decision.BLOCK, "Missing header " .. header .. " for path")
            return decision.block(400, "Bad Request")
        end

        if rule.forbidden and check_header(headers, header, "forbidden") then
            ctx:trace("header_validation", decision.BLOCK, "Forbidden header " .. header .. " for path")
            return decision.block(403, "Forbidden")
        end

        if rule.pattern then
            local val = util.header_get(headers, header) or ""
            if not val:match(rule.pattern) then
                ctx:trace("header_validation", decision.BLOCK, "Header pattern mismatch: " .. header)
                return decision.block(400, "Bad Request")
            end
        end

        ::continue::
    end

    return decision.CONTINUE
end

return M
