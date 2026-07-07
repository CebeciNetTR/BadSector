local decision = require("badsector.decision")
local conditions = require("badsector.conditions")

local M = {
    name = "policies",
    version = "1.0.0",
}

local compiled = {}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    compiled = config.rules or {}
end

--- Evaluate a single condition against context.
---@param rule table
---@param ctx table
---@return boolean
local function eval_condition(rule, ctx)
    return conditions.eval_condition(rule, ctx)
end

--- Evaluate condition tree (and/or groups).
---@param node table
---@param ctx table
---@return boolean
local function eval_tree(node, ctx)
    return conditions.eval_tree(node, ctx)
end

--- Map policy action to decision.
---@param action table
---@return table
local function action_to_decision(action)
    local t = action.type
    if t == "allow" then return decision.ALLOW end
    if t == "continue" then return decision.CONTINUE end
    if t == "return_444" then return decision.RETURN_444 end
    if t == "block" then return decision.block(action.status, action.body) end
    if t == "redirect" then return decision.redirect(action.url, action.status) end
    if t == "js_challenge" then return decision.challenge("js", action) end
    if t == "cookie_challenge" then return decision.challenge("cookie", action) end
    if t == "captcha" then return decision.challenge("captcha", action) end
    if t == "cache" then return decision.cache(action.ttl, action.key) end
    if t == "rate_limit" then return decision.rate_limit(action.retry_after) end
    return decision.CONTINUE
end

function M.run(ctx)
    for _, policy in ipairs(compiled) do
        if policy.enabled ~= false and eval_tree(policy.conditions, ctx) then
            for _, action in ipairs(policy.actions or {}) do
                if action.type == "log" then
                    ngx.log(ngx.INFO, "badsector policy [", policy.id, "]: ", action.message or "")
                elseif action.type == "tag" then
                    ctx:set_var("tag_" .. action.value, true)
                elseif action.type == "skip_module" then
                    ctx:set_var("skip_" .. action.module, true)
                else
                    local d = action_to_decision(action)
                    ctx:trace("policies", d, "Policy matched: " .. (policy.name or policy.id), {
                        policy_id = policy.id,
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
