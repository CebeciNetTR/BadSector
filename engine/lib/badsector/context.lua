--[[
  BadSector RequestContext

  Shared event bus for a single request. Modules read/write enrichments
  and variables through this object. Expensive operations run once via ensure().
]]

local ngx_now = ngx.now

local RequestContext = {}
RequestContext.__index = RequestContext

--- Create a new RequestContext for an incoming request.
---@param site table Site configuration
---@return table
function RequestContext.new(site)
    local headers = ngx.req.get_headers()
    local uri = ngx.var.uri or "/"
    local query = ngx.var.query_string or ""

    local self = setmetatable({
        request = {
            id = ngx.var.request_id or ngx.var.connection .. "-" .. ngx.var.connection_requests,
            method = ngx.req.get_method(),
            uri = uri,
            path = uri,
            query = query,
            headers = headers,
            cookies = headers.cookie,
            body_size = tonumber(ngx.var.content_length) or 0,
            scheme = ngx.var.scheme,
            host = ngx.var.host,
            remote_addr = ngx.var.remote_addr,
            remote_port = tonumber(ngx.var.remote_port),
        },
        site = site,
        enrich = {},
        vars = {},
        trace_steps = {},
        decision = nil,
        response = nil,
        _ensure_cache = {},
        _start = ngx_now(),
    }, RequestContext)

    return self
end

--- Lazy enrichment — runs fn once and caches result on ctx.enrich[key].
---@param key string Enrichment key (e.g. "geo", "asn")
---@param fn function Resolver function
---@return any
function RequestContext:ensure(key, fn)
    if self.enrich[key] ~= nil then
        return self.enrich[key]
    end

    if self._ensure_cache[key] then
        return self.enrich[key]
    end

    self._ensure_cache[key] = true
    local ok, result = pcall(fn)
    if ok then
        self.enrich[key] = result
        return result
    end

    self.enrich[key] = false
    return nil
end

--- Set a custom variable for policy conditions.
---@param name string
---@param value any
function RequestContext:set_var(name, value)
    self.vars[name] = value
end

--- Get a custom variable.
---@param name string
---@param default any|nil
---@return any
function RequestContext:get_var(name, default)
    local v = self.vars[name]
    if v == nil then
        return default
    end
    return v
end

--- Append a trace entry for explainability and analytics.
---@param module_name string
---@param decision table
---@param detail string|nil Human-readable explanation
---@param extra table|nil Additional metadata
function RequestContext:trace(module_name, decision, detail, extra)
    local elapsed = (ngx_now() - self._start) * 1000
    local entry = {
        module = module_name,
        decision = decision.action,
        ms = elapsed,
        detail = detail,
    }

    if extra then
        for k, v in pairs(extra) do
            entry[k] = v
        end
    end

    self.trace_steps[#self.trace_steps + 1] = entry
end

--- Record the terminal decision and optional response metadata.
---@param decision table
---@param response table|nil
function RequestContext:set_decision(decision, response)
    self.decision = decision
    self.response = response
end

--- Serialize trace for logging or response header (debug mode).
---@return string
function RequestContext:trace_json()
    local cjson = require("cjson.safe")
    return cjson.encode(self.trace_steps) or "[]"
end

return RequestContext
