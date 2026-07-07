local decision = require("badsector.decision")

local M = {
    name = "trusted_bots",
    version = "1.0.0",
}

local cfg = {
    enabled = true,
    mark_trusted = true,
    verify_ip = true,
    custom_bots = {},
}

-- Known crawlers: UA substring + IP prefix hints (early filter, not full DNS verify).
local KNOWN_BOTS = {
    {
        name = "Googlebot",
        ua = "Googlebot",
        prefixes = { "66.249.", "64.233.", "72.14.", "209.85.", "216.239." },
    },
    {
        name = "Bingbot",
        ua = "bingbot",
        prefixes = { "157.55.", "207.46.", "40.77.", "13.66.", "13.67." },
    },
    {
        name = "YandexBot",
        ua = "YandexBot",
        prefixes = { "5.255.", "87.250.", "95.108.", "100.43.", "141.8." },
    },
    {
        name = "DuckDuckBot",
        ua = "DuckDuckBot",
        prefixes = { "40.88.", "52.149.", "54.208." },
    },
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.mark_trusted = config.mark_trusted ~= false
    cfg.verify_ip = config.verify_ip ~= false
    cfg.custom_bots = config.custom_bots or {}
end

local function ip_prefix_match(ip, prefixes)
    if not ip or not prefixes then
        return false
    end
    for _, prefix in ipairs(prefixes) do
        if ip:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function match_bot(ua, ip)
    ua = ua or ""

    for _, bot in ipairs(KNOWN_BOTS) do
        if ua:find(bot.ua, 1, true) then
            if not cfg.verify_ip or ip_prefix_match(ip, bot.prefixes) then
                return bot.name, true
            end
            return bot.name, false
        end
    end

    for _, bot in ipairs(cfg.custom_bots) do
        if bot.ua and ua:find(bot.ua, 1, true) then
            if not cfg.verify_ip or ip_prefix_match(ip, bot.prefixes or {}) then
                return bot.name or "custom", true
            end
            return bot.name or "custom", false
        end
    end

    return nil, false
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

    local name, verified = match_bot(ua, ip)

    if not name then
        ctx:trace("trusted_bots", decision.CONTINUE, "Not a verified bot")
        return decision.CONTINUE
    end

    ctx.enrich.bot = {
        name = name,
        verified = verified,
    }

    if verified and cfg.mark_trusted then
        ctx:set_var("trusted_bot", true)
        ctx:trace("trusted_bots", decision.CONTINUE, "Verified bot: " .. name, { bot = name, verified = true })
        return decision.CONTINUE
    end

    ctx:trace("trusted_bots", decision.CONTINUE, "Bot UA without IP verification: " .. name, {
        bot = name,
        verified = false,
    })
    return decision.CONTINUE
end

return M
