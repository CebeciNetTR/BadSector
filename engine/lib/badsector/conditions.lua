--[[
  Shared condition evaluation for policies and custom_rules.
]]

local M = {}

function M.eval_condition(rule, ctx)
    local t = rule.type or rule.field
    local op = rule.operator or "eq"
    local val = rule.value

    if t == "path" then
        local path = ctx.request.path or ""
        if op == "prefix" or op == "starts_with" then
            return path:sub(1, #val) == val
        end
        if op == "eq" then return path == val end
        if op == "regex" or op == "matches" then return path:match(val) ~= nil end
        if op == "contains" then return path:find(val, 1, true) ~= nil end

    elseif t == "method" then
        if op == "eq" then return ctx.request.method == val end
        if op == "in" then
            for _, m in ipairs(val) do
                if ctx.request.method == m then return true end
            end
        end

    elseif t == "host" then
        if op == "eq" then return ctx.request.host == val end
        if op == "contains" then return (ctx.request.host or ""):find(val, 1, true) ~= nil end

    elseif t == "country" then
        local geo = ctx.enrich.geo
        local cc = geo and geo.country or ctx.vars.country
        if not cc then return false end
        if op == "eq" then return cc == val end
        if op == "in" then
            for _, c in ipairs(val) do
                if cc == c then return true end
            end
            return false
        end
        if op == "not_in" then
            for _, c in ipairs(val) do
                if cc == c then return false end
            end
            return true
        end

    elseif t == "asn" then
        local asn = ctx.enrich.asn
        local num = asn and asn.number or ctx.vars.asn
        num = tonumber(num)
        if not num then return false end
        if op == "eq" then return num == tonumber(val) end
        if op == "in" then
            for _, n in ipairs(val) do
                if num == tonumber(n) then return true end
            end
            return false
        end

    elseif t == "ip" then
        if op == "eq" then return ctx.request.remote_addr == val end
        if op == "in" then
            for _, ip in ipairs(val) do
                if ctx.request.remote_addr == ip then return true end
            end
        end

    elseif t == "user_agent" or t == "ua" then
        local ua = ctx.request.headers and ctx.request.headers["User-Agent"] or ""
        if op == "contains" then return ua:find(val, 1, true) ~= nil end
        if op == "regex" or op == "matches" then return ua:match(val) ~= nil end
        if op == "eq" then return ua == val end

    elseif t == "header" then
        local name = rule.name or rule.header
        local headers = ctx.request.headers or {}
        local hv = headers[name]
        if not hv then
            for k, v in pairs(headers) do
                if k:lower() == (name or ""):lower() then
                    hv = v
                    break
                end
            end
        end
        hv = hv or ""
        if op == "exists" then return hv ~= "" end
        if op == "eq" then return hv == val end
        if op == "contains" then return hv:find(val, 1, true) ~= nil end
        if op == "regex" or op == "matches" then return hv:match(val) ~= nil end

    elseif t == "variable" then
        local v = ctx:get_var(rule.name)
        if op == "eq" then return v == val end
        if op == "gt" then return tonumber(v) and tonumber(v) > tonumber(val) end
        if op == "contains" then return tostring(v or ""):find(tostring(val), 1, true) ~= nil end

    elseif t == "rate" then
        local count = ctx:get_var("rate_count")
        if ctx.enrich.rate then
            count = ctx.enrich.rate.count
        end
        count = tonumber(count)
        if not count then return false end
        local threshold = tonumber(val) or 0
        if op == "gt" then return count > threshold end
        if op == "gte" then return count >= threshold end
        if op == "lt" then return count < threshold end
        if op == "lte" then return count <= threshold end
        if op == "eq" then return count == threshold end
    end

    return false
end

function M.eval_tree(node, ctx)
    if not node then
        return false
    end

    if node.rules or node.conditions then
        local children = node.rules or node.conditions
        local op = node.operator or "and"
        if op == "and" then
            for _, rule in ipairs(children) do
                if not M.eval_tree(rule, ctx) then
                    return false
                end
            end
            return true
        elseif op == "or" then
            for _, rule in ipairs(children) do
                if M.eval_tree(rule, ctx) then
                    return true
                end
            end
            return false
        end
    end

    return M.eval_condition(node, ctx)
end

return M
