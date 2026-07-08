--[[
  BadSector request entry point — called from nginx access_by_lua_block.
]]

local config = require("badsector.config")
local pipeline = require("badsector.pipeline")

local _M = {}

function _M.init_worker()
    config.load(os.getenv("BADSECTOR_RUNTIME") or "/etc/badsector/runtime")
    pipeline.init_worker(config.all())
end

function _M.handle()
    local uri = ngx.var.uri
    if uri == "/badsector/health" or uri == "/badsector/admin/reload" then
        return
    end

    local acme = require("badsector.acme")
    if acme.is_challenge_path(uri) then
        -- ACME is served by nginx location content_by_lua (acme.lua).
        return
    end

    local host = ngx.var.host
    local site = config.resolve(host)

    if not site then
        ngx.status = 404
        ngx.say("Site not configured")
        return ngx.exit(404)
    end

    local canonical = require("badsector.canonical")
    if canonical.enforce(site, host) then
        return
    end

    local ctx = pipeline.run(site)

    local settings = site.settings or {}

    local metrics = require("badsector.metrics")
    metrics.record(site.id, ctx)

    -- Debug trace header (enable per site in settings)
    if settings.debug_trace then
        ngx.header["X-BadSector-Trace"] = ctx:trace_json()
    end

    -- Live trace buffer for dashboard explainability
    if settings.live_trace then
        local trace_store = require("badsector.trace")
        trace_store.record(site.id, ctx)
    end

    if ctx.decision and ctx.decision.action == "ALLOW" then
        local origin_headers = require("badsector.origin_headers")
        origin_headers.apply(ctx, settings)
        return
    end
end

function _M.admin_reload()
    local admin = require("badsector.admin")
    admin.handle_reload()
end

return _M
