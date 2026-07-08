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



local function rule_expr(rule)
    if not rule or type(rule.match) ~= "table" then
        return ""
    end
    local e = rule.match.expr
    if type(e) ~= "string" then
        return ""
    end
    return (e:gsub("^%s+", ""):gsub("%s+$", ""))
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

    local t = type(action.type) == "string" and string.lower(action.type) or action.type

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

    M.reload(config or {})



    if not cfg.enabled then

        ctx:set_module_detail(M.name, "module disabled in config")

        return decision.CONTINUE

    end



    if #cfg.rules == 0 then

        local msg = "no rules loaded — save Custom Rules tab and reload runtime"

        ngx.log(ngx.WARN, "badsector custom_rules: enabled but no rules loaded for site ",

            ctx.site and ctx.site.id or "?", " path=", ctx.request and ctx.request.path or "?")

        ngx.header["X-BadSector-Rules"] = "loaded=0"

        ctx:set_module_detail(M.name, msg)

        return decision.CONTINUE

    end



    ngx.header["X-BadSector-Rules"] = "loaded=" .. tostring(#cfg.rules)



    local path = ctx.request and ctx.request.path or "?"

    local skipped_expr = 0

    local eval_errors = 0



    local last_expr = ""
    local last_eval = false

    for _, rule in ipairs(cfg.rules) do

        if rule.enabled ~= false then

            local expr_text = rule_expr(rule)

            if expr_text == "" then

                skipped_expr = skipped_expr + 1

                ngx.log(ngx.WARN, "badsector custom_rules: rule has empty expr [",

                    rule.name or rule.id or "?", "] — skipped")

            else
                last_expr = expr_text
                local ok, matched = pcall(expr.eval_match, rule.match, ctx)

                if not ok then

                    eval_errors = eval_errors + 1

                    ngx.log(ngx.WARN, "badsector custom_rules: eval error [",

                        rule.name or rule.id or "?", "]: ", matched)

                    if not cfg.fail_open then

                        ctx:set_module_detail(M.name, "eval error: " .. tostring(matched))

                        return decision.block(500, "Rule evaluation error")

                    end

                elseif matched then
                    last_eval = true
                    local d = action_to_decision(rule.action)
                    local atype = rule.action and rule.action.type
                    if type(atype) == "string" then
                        atype = string.lower(atype)
                    end
                    if atype == "set_var" then

                        ctx:set_var(rule.action.name, rule.action.value)

                        ctx:trace("custom_rules", decision.CONTINUE, rule.name or rule.id or "set_var")

                    elseif atype == "log" then

                        ngx.log(ngx.INFO, "badsector custom_rules [", rule.id or "?", "]: ", rule.action.message or "")

                        ctx:trace("custom_rules", decision.CONTINUE, rule.name or "log")

                    else
                        ctx:trace("custom_rules", d, rule.name or rule.id or "matched", {
                            rule_id = rule.id,
                            expr = expr_text,
                        })
                        if decision.is_terminal(d) then
                            ngx.header["X-BadSector-Rules"] = "matched=" .. (rule.name or rule.id or "?")
                            return d
                        end
                        ngx.log(ngx.WARN, "badsector custom_rules: rule matched but action not terminal [",
                            rule.name or rule.id or "?", "] type=", tostring(rule.action and rule.action.type))
                    end

                end

            end

        end

    end



    local detail = string.format("%d rule(s), path=%s, no match", #cfg.rules, path)

    if skipped_expr > 0 then

        detail = detail .. string.format("; %d skipped (empty expr — re-save rules)", skipped_expr)

    end

    if eval_errors > 0 then

        detail = detail .. string.format("; %d eval error(s), fail_open=%s", eval_errors, tostring(cfg.fail_open))

    end

    if last_expr ~= "" then
        ngx.header["X-BadSector-Rules-Check"] = string.format(
            "path=%s; expr=%s; matched=%s", path, last_expr, tostring(last_eval))
    end

    ctx:set_module_detail(M.name, detail)

    return decision.CONTINUE

end



return M


