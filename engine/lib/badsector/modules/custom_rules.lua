local cjson = require("cjson.safe")
local decision = require("badsector.decision")
local expr = require("badsector.expr")

local M = {
    name = "custom_rules",
    version = "1.0.0",
}

local cfg = {
    enabled = true,
    rules = {},
    fail_open = true,
}

local function normalize_config(config)
    if type(config) == "string" then
        local decoded = cjson.decode(config)
        if type(decoded) == "table" then
            return decoded
        end
        return {}
    end
    return config or {}
end

local function collect_rules(rules)
    local out = {}
    if type(rules) ~= "table" then
        return out
    end

    if #rules > 0 then
        for i = 1, #rules do
            if type(rules[i]) == "table" then
                out[#out + 1] = rules[i]
            end
        end
        return out
    end

    for _, rule in pairs(rules) do
        if type(rule) == "table" then
            out[#out + 1] = rule
        end
    end
    return out
end

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = normalize_config(config)
    cfg.enabled = config.enabled ~= false
    cfg.rules = collect_rules(config.rules)
    cfg.fail_open = config.fail_open ~= false

    table.sort(cfg.rules, function(a, b)
        return (a.priority or 100) < (b.priority or 100)
    end)
end

local function action_to_decision(action)
    if not action then
        return decision.CONTINUE
    end

    local t = action.type
    if t == "allow" then return decision.ALLOW end
    if t == "continue" then return decision.CONTINUE end
    if t == "return_444" then return decision.RETURN_444 end
    if t == "block" then
        return decision.block(action.status or 403, action.body or "Forbidden")
    end
    if t == "redirect" then return decision.redirect(action.url, action.status or 302) end
    if t == "js_challenge" then return decision.challenge("js", action) end
    if t == "cookie_challenge" then return decision.challenge("cookie", action) end
    if t == "rate_limit" then return decision.rate_limit(action.retry_after or 60) end
    if t == "custom" then
        return decision.custom(action.status or 200, action.body, action.headers)
    end
    return decision.CONTINUE
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end

    if not cfg.enabled then
        return decision.CONTINUE
    end

    if #cfg.rules == 0 then
        ngx.log(ngx.WARN, "badsector custom_rules: enabled but no rules loaded for site ",
            ctx.site and ctx.site.id or "?")
        return decision.CONTINUE
    end

    for _, rule in ipairs(cfg.rules) do
        if rule.enabled ~= false then
            local ok, matched = pcall(expr.eval_match, rule.match, ctx)
            if not ok then
                ngx.log(ngx.WARN, "badsector custom_rules: eval error [",
                    rule.name or rule.id or "?", "]: ", matched)
                if not cfg.fail_open then
                    return decision.block(500, "Rule evaluation error")
                end
            elseif matched then
                if rule.action and rule.action.type == "set_var" then
                    ctx:set_var(rule.action.name, rule.action.value)
                    ctx:trace("custom_rules", decision.CONTINUE, rule.name or rule.id or "set_var")
                elseif rule.action and rule.action.type == "log" then
                    ngx.log(ngx.INFO, "badsector custom_rules [", rule.id or "?", "]: ", rule.action.message or "")
                    ctx:trace("custom_rules", decision.CONTINUE, rule.name or "log")
                else
                    local d = action_to_decision(rule.action)
                    ctx:trace("custom_rules", d, rule.name or rule.id or "matched", {
                        rule_id = rule.id,
                    })
                    if decision.is_terminal(d) then
                        return d
                    end
                end
            end
        end
    end

    return decision.CONTINUE
end

return M
