--[[
  BadSector request entry point — called from nginx access_by_lua_block.
]]

local config = require("badsector.config")
local pipeline = require("badsector.pipeline")
local decision = require("badsector.decision")
local executor = require("badsector.executor")

local _M = {}

local DEFAULT_BACKEND = "http://backend:80"

local function normalize_backend(url)
    if type(url) ~= "string" then
        return nil
    end
    url = url:match("^%s*(.-)%s*$")
    if url == "" then
        return nil
    end
    if not url:find("://") then
        url = "http://" .. url
    end
    return url
end

--- Ensure reverse_proxy backend is set even if the module was skipped/disabled.
local function ensure_backend(site)
    local current = ngx.var.badsector_backend
    if current and current ~= "" and current ~= DEFAULT_BACKEND then
        return current
    end

    for _, stage in ipairs(site.pipeline or {}) do
        if stage.module == "reverse_proxy" and stage.enabled ~= false then
            local cfg = stage.config or {}
            local url = normalize_backend(cfg.backend_url)
            if not url and cfg.upstream and cfg.upstream ~= "" then
                url = "http://" .. cfg.upstream
            end
            if url then
                ngx.var.badsector_backend = url
                return url
            end
        end
    end

    return current
end

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

    if settings.debug_trace then
        ngx.header["X-BadSector-Trace"] = ctx:trace_json()
    end

    if settings.live_trace then
        local trace_store = require("badsector.trace")
        trace_store.record(site.id, ctx)
    end

    local d = ctx.decision or decision.ALLOW

    if d.action == "ALLOW" then
        ensure_backend(site)

        local origin_headers = require("badsector.origin_headers")
        local ok, err = pcall(origin_headers.apply, ctx, settings)
        if not ok then
            ngx.log(ngx.ERR, "badsector: origin_headers error: ", err)
            ngx.status = 500
            ngx.say("Internal Server Error")
            return ngx.exit(500)
        end
        return
    end

    if decision.is_terminal(d) then
        executor.apply(ctx)
        return
    end
end

function _M.admin_reload()
    local admin = require("badsector.admin")
    admin.handle_reload()
end

return _M
