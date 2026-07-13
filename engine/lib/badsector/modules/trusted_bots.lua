local decision = require("badsector.decision")
local bot_verify = require("badsector.bot_verify")

local M = {
    name = "trusted_bots",
    version = "2.0.0",
}

local cfg = {
    enabled = true,
    mark_trusted = true,
    verify_ip = true,
    -- Dogrulanmis bot'u tum pipeline'dan (WAF, rate-limit, geoip, custom_rules,
    -- challenge'lar) muaf tut: terminal ALLOW ile dogrudan backend'e gonder.
    -- Hem "tum korumalardan muaf" hem de "ucuz" (pahali WAF dahil her sey atlanir).
    bypass_pipeline = true,
    custom_bots = {},
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.mark_trusted = config.mark_trusted ~= false
    cfg.verify_ip = config.verify_ip ~= false
    cfg.bypass_pipeline = config.bypass_pipeline ~= false
    cfg.custom_bots = config.custom_bots or {}
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end

    if not cfg.enabled then
        return decision.CONTINUE
    end

    local headers = ctx.request.headers or {}
    local ua = headers["User-Agent"] or headers["user-agent"] or ""
    local ip = ctx.request.remote_addr

    local name, verified = bot_verify.verify(ip, ua)

    if not name then
        ctx:trace("trusted_bots", decision.CONTINUE, "Bot degil")
        return decision.CONTINUE
    end

    ctx.enrich.bot = {
        name = name,
        verified = verified,
    }

    if not verified then
        -- UA bot gibi ama IP dogrulanmadi (muhtemel sahtekar) -> normal pipeline.
        ctx:trace("trusted_bots", decision.CONTINUE, "Dogrulanmamis bot UA: " .. name, {
            bot = name,
            verified = false,
        })
        return decision.CONTINUE
    end

    if cfg.mark_trusted then
        ctx:set_var("trusted_bot", true)
    end

    if cfg.bypass_pipeline then
        ctx:trace("trusted_bots", decision.ALLOW,
            "Dogrulanmis bot: " .. name .. " — tum korumalardan muaf (bypass)", {
            bot = name,
            verified = true,
            bypass = true,
        })
        return decision.ALLOW
    end

    ctx:trace("trusted_bots", decision.CONTINUE, "Dogrulanmis bot: " .. name, {
        bot = name,
        verified = true,
    })
    return decision.CONTINUE
end

return M
