local decision = require("badsector.decision")
local coraza = require("badsector.coraza")

local M = {
    name = "managed_waf",
    version = "1.0.0",
}

--- Per-worker WAF engine (reloaded on config change).
local engine = nil
local current_config = nil

local function normalize_config(config)
    config = config or {}
    local defaults = coraza.default_config()
    for k, v in pairs(defaults) do
        if config[k] == nil then
            config[k] = v
        end
    end
    return config
end

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = normalize_config(config)
    current_config = config
    engine = coraza.new(config)
end

function M.run(ctx, config)
    config = normalize_config(config or current_config)

    if not engine then
        M.reload(config)
    end

    local match = coraza.process(engine, ctx)

    if not match then
        ctx.enrich.waf = { matched = false, backend = engine and engine.backend or "none" }
        return decision.CONTINUE
    end

    ctx.enrich.waf = {
        matched = true,
        rule_id = match.id,
        message = match.msg,
        zone = match.zone,
        backend = match.backend,
    }
    ctx:set_var("waf_matched", true)
    ctx:set_var("waf_rule_id", match.id)

    local detail = string.format("Rule %s: %s (zone: %s)", match.id, match.msg, match.zone or "request")
    local mode = config.mode or "block"

    if mode == "detect" then
        ctx:trace(M.name, decision.CONTINUE, "[detect] " .. detail, {
            rule_id = match.id,
            mode = mode,
        })
        if config.audit then
            ngx.log(ngx.WARN, "badsector waf [detect] ", detail, " ip=", ctx.request.remote_addr)
        end
        return decision.CONTINUE
    end

    ctx:trace(M.name, decision.block(403, "Request blocked by WAF"), detail, {
        rule_id = match.id,
        mode = mode,
    })

    if config.audit then
        ngx.log(ngx.WARN, "badsector waf [block] ", detail, " ip=", ctx.request.remote_addr)
    end

    return decision.block(403, "Request blocked by WAF", {
        ["X-BadSector-WAF-Rule"] = match.id,
    })
end

return M
