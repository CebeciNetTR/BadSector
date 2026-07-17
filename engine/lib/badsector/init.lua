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

    local runtime = os.getenv("BADSECTOR_RUNTIME") or "/etc/badsector/runtime"

    config.load(runtime)

    config.mark_loaded()

    pipeline.init_worker(config.all())

end



--- Ban lookup with shared-dict negatif cache. Istek basina Redis GET yerine IP
--- basina ~5s'de bir Redis'e gidilir; flood altinda Redis QPS'i cok dusuk kalir.
local function is_banned_cached(rip)
    if not rip or rip == "" then
        return false
    end
    local dict = ngx.shared.badsector_bans
    if dict then
        local cached = dict:get(rip)
        if cached ~= nil then
            return cached == 1
        end
    end
    local banned = false
    local redis = require("badsector.redis")
    local red = redis.connect()
    if red then
        local val = red:get("bs:ban:" .. rip)
        if val and val ~= ngx.null then
            banned = true
        end
        redis.keepalive(red)
    end
    if dict then
        -- Banli: 30s cache; degil: 5s (yeni ban en fazla 5s gecikmeyle gorulur).
        dict:set(rip, banned and 1 or 0, banned and 30 or 5)
    end
    return banned
end

function _M.handle()

    config.sync_if_needed()

    local uri = ngx.var.uri

    -- Ucuz kisa devre: health/reload/acme Redis'e DOKUNMADAN doner. Flood altinda
    -- HAProxy'nin engine health-check'i canli kalir -> engine DOWN sayilmaz.
    if uri == "/badsector/health" or uri == "/badsector/admin/reload" then
        return
    end

    local acme = require("badsector.acme")
    if acme.is_challenge_path(uri) then
        return
    end

    local client_ip = require("badsector.client_ip")
    local rip = client_ip.from_request()
    ngx.var.badsector_client_ip = rip or ""

    local trusted_ips = require("badsector.trusted_ips")
    local is_trusted = trusted_ips.is(rip)

    -- Ban check: shared-dict negatif cache (istek basina Redis GET yerine ~5s'de bir).
    -- Trusted IP asla ban drop almaz (Redis'te kalsa bile).
    if not is_trusted and is_banned_cached(rip) then
        require("badsector.metrics").incr("BAN_DROP")
        return executor.drop()
    end



    local host = ngx.var.host

    local site = config.resolve(host)

    if site and site.id then
        ngx.header["X-BadSector-Site"] = site.id
    end



    if not site then

        require("badsector.metrics").incr("NO_SITE")

        return executor.drop()

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

        local canonical = require("badsector.canonical")

        if canonical.enforce(site, host) then

            return

        end



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

