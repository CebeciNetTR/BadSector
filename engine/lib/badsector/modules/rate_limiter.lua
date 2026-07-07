local decision = require("badsector.decision")
local ratelimit = require("badsector.ratelimit")
local redis = require("badsector.redis")

local M = {
    name = "rate_limiter",
    version = "1.0.0",
}

local global_config = {}

function M.init(config)
    M.reload(config)
    -- Redis is probed on first request; cosockets are unavailable in init_worker_by_lua.
end
function M.reload(config)
    config = config or {}
    global_config = {
        redis = config.redis,
        fail_mode = config.fail_mode or "open",
        use_redis = config.use_redis,
    }
    if config.redis then
        redis.configure(config.redis)
    end
end

--- Store rate state on context for downstream modules and policies.
---@param ctx table
---@param rule table
---@param info table
local function set_rate_enrichment(ctx, rule, info)
    ctx.enrich.rate = {
        rule_id = rule.id,
        rule_name = rule.name,
        count = info.count,
        limit = info.limit,
        burst = info.burst or 0,
        remaining = info.remaining,
        window = info.window,
        backend = info.backend,
    }
    ctx:set_var("rate_count", info.count)
    ctx:set_var("rate_limit", info.limit)
    ctx:set_var("rate_remaining", info.remaining)
end

function M.run(ctx, config)
    config = config or {}
    local rules = config.rules or {}
    local site_id = ctx.site and ctx.site.id or "default"
    local fail_mode = config.fail_mode or global_config.fail_mode or "open"
    local use_redis = config.use_redis
    if use_redis == nil then
        use_redis = global_config.use_redis
    end
    if use_redis == nil then
        use_redis = true
    end

    for _, rule in ipairs(rules) do
        if ratelimit.rule_matches(rule, ctx) then
            if rule.key_by == "header" and rule.header_name then
                ctx._rate_header_name = rule.header_name
            end
            if rule.key_by == "cookie" and rule.cookie_name then
                ctx._rate_cookie_name = rule.cookie_name
            end

            local key = ratelimit.build_key(site_id, rule.id or rule.name, rule.key_by or "ip", ctx)
            local allowed, info = ratelimit.check({
                key = key,
                limit = rule.limit,
                burst = rule.burst,
                window = rule.window,
                use_redis = use_redis,
                fail_mode = fail_mode,
            })

            set_rate_enrichment(ctx, rule, info)

            if info.bypass then
                ctx:trace(M.name, decision.CONTINUE, "Rate limit bypass (backend unavailable)", {
                    rule_id = rule.id,
                    backend = info.backend,
                })
                return decision.CONTINUE
            end

            if not allowed then
                local retry_after = info.retry_after or ratelimit.parse_window(rule.window)
                local detail = string.format(
                    "Rule '%s' exceeded: %d/%d requests in %ds window",
                    rule.name or rule.id or "unnamed",
                    info.count,
                    info.effective_limit or rule.limit,
                    info.window or ratelimit.parse_window(rule.window)
                )

                local d = decision.rate_limit(retry_after, {
                    limit = info.limit,
                    remaining = 0,
                    rule_id = rule.id,
                    rule_name = rule.name,
                    count = info.count,
                })

                ctx:trace(M.name, d, detail, {
                    rule_id = rule.id,
                    count = info.count,
                    limit = info.limit,
                    remaining = 0,
                    retry_after = retry_after,
                    backend = info.backend,
                })

                return d
            end

            ctx:trace(M.name, decision.CONTINUE, string.format(
                "Rule '%s': %d/%d remaining %d",
                rule.name or rule.id or "unnamed",
                info.count,
                info.effective_limit or rule.limit,
                info.remaining
            ), {
                rule_id = rule.id,
                count = info.count,
                limit = info.limit,
                remaining = info.remaining,
                backend = info.backend,
            })
        end
    end

    return decision.CONTINUE
end

return M
