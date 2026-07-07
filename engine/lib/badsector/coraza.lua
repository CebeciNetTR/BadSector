--[[
  BadSector Coraza WAF Engine

  Abstraction over Coraza with a built-in rules fallback for development.
  Production: install Coraza OpenResty bindings and CRS rules under
  /etc/badsector/coraza/
]]

local _M = {}

local BACKEND_BUILTIN = "builtin"
local BACKEND_CORAZA = "coraza"

--- Built-in CRS-inspired rules (used when Coraza library is unavailable).
local BUILTIN_RULES = {
    { id = "942100", level = 1, msg = "SQL Injection", pattern = "(union[%s]+select|select.-%s-from[%s]+|insert[%s]+into|delete[%s]+from|drop[%s]+table)" },
    { id = "941100", level = 1, msg = "XSS attack", pattern = "<[%s]*script" },
    { id = "930100", level = 1, msg = "Path traversal", pattern = "%.%./" },
    { id = "920450", level = 2, msg = "HTTP protocol violation", pattern = "%x00" },
    { id = "932100", level = 2, msg = "Remote command execution", pattern = "(;[%s]*|%||%&%&)[%s]*(cat|wget|curl|bash|sh|cmd)" },
}

--- Try to load native Coraza bindings.
---@return table|nil engine
---@return string|nil err
local function load_coraza_engine(config)
    local ok, coraza = pcall(require, "coraza")
    if not ok then
        ok, coraza = pcall(require, "resty.coraza")
    end
    if not ok or not coraza then
        return nil, "coraza library not installed"
    end

    if coraza.new then
        local engine, err = coraza.new({
            ruleset = config.ruleset or "coraza-crs",
            paranoia_level = config.paranoia_level or 1,
            rules_dir = config.rules_dir or "/etc/badsector/coraza/rules",
        })
        return engine, err
    end

    return nil, "coraza.new not available"
end

--- Load RULE lines from mounted CRS files (dev/prod rules_dir).
---@param rules_dir string
---@return table
local function load_file_rules(rules_dir)
    local rules = {}
    local path = (rules_dir or "") .. "/badsector-crs.conf"
    local f = io.open(path, "r")
    if not f then
        return rules
    end

    for line in f:lines() do
        local id, level, msg, pattern = line:match('^RULE id=(%S+) level=(%d+) msg="([^"]+)" pattern=(.+)$')
        if id and pattern then
            rules[#rules + 1] = {
                id = id,
                level = tonumber(level) or 1,
                msg = msg,
                pattern = pattern,
            }
        end
    end

    f:close()
    return rules
end

--- Compile builtin rules filtered by paranoia level.
---@param paranoia_level number
---@param rules_dir string|nil
---@return table
local function compile_builtin_rules(paranoia_level, rules_dir)
    local rules = {}
    for _, rule in ipairs(BUILTIN_RULES) do
        if rule.level <= (paranoia_level or 1) then
            rules[#rules + 1] = rule
        end
    end

    for _, rule in ipairs(load_file_rules(rules_dir)) do
        if rule.level <= (paranoia_level or 1) then
            rules[#rules + 1] = rule
        end
    end

    return rules
end

--- Create a WAF engine instance from config.
---@param config table
---@return table engine
function _M.new(config)
    config = config or {}

    local coraza_engine, err = load_coraza_engine(config)
    if coraza_engine then
        ngx.log(ngx.INFO, "badsector waf: using Coraza engine")
        return {
            backend = BACKEND_CORAZA,
            engine = coraza_engine,
            config = config,
        }
    end

    ngx.log(ngx.NOTICE, "badsector waf: Coraza unavailable (", err or "unknown", "), using builtin rules")
    return {
        backend = BACKEND_BUILTIN,
        rules = compile_builtin_rules(config.paranoia_level or 1, config.rules_dir),
        config = config,
    }
end

--- Collect request fragments to inspect.
---@param ctx table RequestContext
---@return table targets { name, value }[]
local function collect_targets(ctx)
    local targets = {
        { name = "uri", value = ctx.request.uri or "" },
        { name = "path", value = ctx.request.path or "" },
        { name = "query", value = ctx.request.query or "" },
    }

    local headers = ctx.request.headers or {}
    if headers["User-Agent"] then
        targets[#targets + 1] = { name = "User-Agent", value = headers["User-Agent"] }
    end
    if headers["Cookie"] then
        targets[#targets + 1] = { name = "Cookie", value = headers["Cookie"] }
    end
    if headers["Referer"] then
        targets[#targets + 1] = { name = "Referer", value = headers["Referer"] }
    end

    return targets
end

--- Scan with builtin rules.
---@param waf table
---@param ctx table
---@return table|nil match { id, msg, zone }
local function scan_builtin(waf, ctx)
    local targets = collect_targets(ctx)

    for _, rule in ipairs(waf.rules or {}) do
        for _, target in ipairs(targets) do
            local val = target.value:lower()
            if val ~= "" and val:match(rule.pattern) then
                return {
                    id = rule.id,
                    msg = rule.msg,
                    zone = target.name,
                    backend = BACKEND_BUILTIN,
                }
            end
        end
    end

    return nil
end

--- Scan with Coraza engine.
---@param waf table
---@param ctx table
---@return table|nil match
local function scan_coraza(waf, ctx)
    local engine = waf.engine
    if not engine then
        return nil
    end

    if engine.process_request then
        local result = engine:process_request({
            uri = ctx.request.uri,
            method = ctx.request.method,
            headers = ctx.request.headers,
            remote_addr = ctx.request.remote_addr,
        })
        if result and result.matched then
            return {
                id = result.rule_id or "coraza",
                msg = result.message or "Coraza rule matched",
                zone = result.zone or "request",
                backend = BACKEND_CORAZA,
            }
        end
    end

    return nil
end

--- Check if path is excluded from WAF.
---@param path string
---@param exclude_paths table
---@return boolean
local function is_excluded(path, exclude_paths)
    for _, pattern in ipairs(exclude_paths or {}) do
        if pattern == "/*" or pattern == "*" then
            return true
        end
        if pattern:sub(-1) == "*" then
            local prefix = pattern:sub(1, -2)
            if path:sub(1, #prefix) == prefix then
                return true
            end
        elseif path == pattern then
            return true
        end
    end
    return false
end

--- Process request through WAF.
---@param waf table
---@param ctx table RequestContext
---@return table|nil match nil if clean
function _M.process(waf, ctx)
    if is_excluded(ctx.request.path, waf.config.exclude_paths) then
        return nil
    end

    if waf.backend == BACKEND_CORAZA then
        return scan_coraza(waf, ctx)
    end

    return scan_builtin(waf, ctx)
end

--- Default module configuration.
---@return table
function _M.default_config()
    return {
        ruleset = "coraza-crs",
        paranoia_level = 1,
        mode = "block",
        exclude_paths = { "/badsector/health" },
        audit = true,
        rules_dir = "/etc/badsector/coraza/rules",
    }
end

return _M
