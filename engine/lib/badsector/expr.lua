--[[
  Safe expression evaluator for custom_rules (no loadstring / arbitrary Lua).
  Syntax examples:
    path.starts_with("/admin")
    country in ["TR", "DE"]
    header.User-Agent contains "curl"
    ip == "1.2.3.4" and method == "POST"
]]

local conditions = require("badsector.conditions")
local util = require("badsector.util")

local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_top_level(s, sep)
    local parts = {}
    local depth = 0
    local start = 1
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
        elseif depth == 0 and s:sub(i, i + #sep - 1) == sep then
            parts[#parts + 1] = trim(s:sub(start, i - 1))
            start = i + #sep
        end
    end
    parts[#parts + 1] = trim(s:sub(start))
    return parts
end

local function parse_value(raw)
    raw = trim(raw)
    if raw:sub(1, 1) == '"' and raw:sub(-1) == '"' then
        return raw:sub(2, -2)
    end
    if raw:sub(1, 1) == "'" and raw:sub(-1) == "'" then
        return raw:sub(2, -2)
    end
    if raw:sub(1, 1) == "[" then
        local list = {}
        local inner = raw:sub(2, -2)
        for part in inner:gmatch("[^,]+") do
            part = trim(part)
            part = part:gsub('^"', ""):gsub('"$', "")
            part = part:gsub("^'", ""):gsub("'$", "")
            if part ~= "" then
                list[#list + 1] = part
            end
        end
        return list
    end
    local num = tonumber(raw)
    if num then
        return num
    end
    return raw
end

local function field_value(field, ctx)
    field = trim(field)
    if field:sub(1, 7) == "header." then
        local name = field:sub(8)
        local headers = ctx.request.headers or {}
        local hv = headers[name]
        if not hv then
            for k, v in pairs(headers) do
                if k:lower() == name:lower() then
                    hv = v
                    break
                end
            end
        end
        return hv or ""
    end

    if field == "path" then return ctx.request.path or "" end
    if field == "method" then return ctx.request.method or "" end
    if field == "host" then return ctx.request.host or "" end
    if field == "ip" then return ctx.request.remote_addr or "" end
    if field == "ua" or field == "user_agent" then
        return util.header_get(ctx.request.headers, "User-Agent") or ""
    end
    if field == "country" then
        local geo = ctx.enrich.geo
        return geo and geo.country or ctx.vars.country or ""
    end
    if field == "asn" then
        local asn = ctx.enrich.asn
        return asn and asn.number or ctx.vars.asn or ""
    end
    return ctx:get_var(field)
end

local function eval_atom(expr, ctx)
    expr = trim(expr)
    if expr == "" then
        return false
    end

    if expr:sub(1, 1) == "(" and expr:sub(-1) == ")" then
        return M.eval(expr:sub(2, -2), ctx)
    end

    -- field in ["a","b"]
    local field, list_raw = expr:match("^([%w_%.%-]+)%s+in%s+(%b[])$")
    if field and list_raw then
        local val = field_value(field, ctx)
        local list = parse_value(list_raw)
        for _, item in ipairs(list) do
            if tostring(val) == tostring(item) then
                return true
            end
        end
        return false
    end

    -- field not in ["a","b"]
    field, list_raw = expr:match("^([%w_%.%-]+)%s+not%s+in%s+(%b[])$")
    if field and list_raw then
        local val = field_value(field, ctx)
        local list = parse_value(list_raw)
        for _, item in ipairs(list) do
            if tostring(val) == tostring(item) then
                return false
            end
        end
        return true
    end

    -- field.method("arg") or field contains "x"
    local f, op, arg = expr:match("^([%w_%.%-]+)%.([%w_]+)%((.-)%)$")
    if f and op and arg then
        local val = field_value(f, ctx)
        arg = parse_value(arg)
        if op == "starts_with" or op == "prefix" then
            return val:sub(1, #arg) == arg
        end
        if op == "contains" then
            return val:find(arg, 1, true) ~= nil
        end
        if op == "matches" or op == "regex" then
            return val:match(arg) ~= nil
        end
        if op == "eq" then
            return tostring(val) == tostring(arg)
        end
    end

    f, op, arg = expr:match("^([%w_%.%-]+)%s+contains%s+(.+)$")
    if f and arg then
        local val = field_value(f, ctx)
        local needle = parse_value(arg)
        if type(val) ~= "string" then
            val = tostring(val or "")
        end
        if f == "path" or f == "host" or f == "ua" or f == "user_agent" then
            return val:lower():find(needle:lower(), 1, true) ~= nil
        end
        return val:find(needle, 1, true) ~= nil
    end

    f, op, arg = expr:match("^([%w_%.%-]+)%s*==%s*(.+)$")
    if f and arg then
        return tostring(field_value(f, ctx)) == tostring(parse_value(arg))
    end

    f, op, arg = expr:match("^([%w_%.%-]+)%s*!=%s*(.+)$")
    if f and arg then
        return tostring(field_value(f, ctx)) ~= tostring(parse_value(arg))
    end

    return false
end

function M.eval(expr, ctx)
    if not expr or expr == "" then
        return false
    end

    expr = trim(expr)

    if expr:sub(1, 4) == "not " then
        local inner = trim(expr:sub(5))
        if inner:sub(1, 1) == "(" and inner:sub(-1) == ")" then
            return not M.eval(inner:sub(2, -2), ctx)
        end
        return not M.eval(inner, ctx)
    end

    local or_parts = split_top_level(expr, " or ")
    if #or_parts > 1 then
        for _, part in ipairs(or_parts) do
            if M.eval(part, ctx) then
                return true
            end
        end
        return false
    end

    local and_parts = split_top_level(expr, " and ")
    if #and_parts > 1 then
        for _, part in ipairs(and_parts) do
            if not eval_atom(part, ctx) then
                return false
            end
        end
        return true
    end

    return eval_atom(expr, ctx)
end

function M.eval_match(match, ctx)
    if not match then
        return false
    end
    local expr_str = match.expr
    if type(expr_str) == "string" then
        expr_str = trim(expr_str)
    end
    if expr_str and expr_str ~= "" then
        return M.eval(expr_str, ctx)
    end
    return conditions.eval_tree(match, ctx)
end

return M
