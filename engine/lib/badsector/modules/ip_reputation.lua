local decision = require("badsector.decision")
local redis = require("badsector.redis")

local M = {
    name = "ip_reputation",
    version = "1.0.0",
}

local cfg = {
    enabled = true,
    block_ips = {},
    block_cidrs = {},
    use_redis_feed = false,
    redis_key = "badsector:reputation:bad",
    action = "block",
    fail_open = true,
}

function M.init(config)
    M.reload(config)
end

function M.reload(config)
    config = config or {}
    cfg.enabled = config.enabled ~= false
    cfg.block_ips = config.block_ips or {}
    cfg.block_cidrs = config.block_cidrs or {}
    cfg.use_redis_feed = config.use_redis_feed == true
    cfg.redis_key = config.redis_key or "badsector:reputation:bad"
    cfg.action = config.action or "block"
    cfg.fail_open = config.fail_open ~= false
end

local function matches_entry(ip, entry)
    if ip == entry then
        return true
    end

    local prefix = entry:match("^([^/]+)/")
    if prefix and ip:sub(1, #prefix) == prefix then
        return true
    end

    return false
end

local function ip_in_list(ip, list)
    for _, entry in ipairs(list) do
        if matches_entry(ip, entry) then
            return true
        end
    end
    return false
end

local function redis_blocked(ip)
    local red, err = redis.connect()
    if not red then
        return nil, err
    end

    local ok, is_member = red:sismember(cfg.redis_key, ip)
    redis.keepalive(red)

    if not ok then
        return nil, is_member
    end

    return is_member == 1, nil
end

function M.run(ctx, config)
    if config then
        M.reload(config)
    end

    if not cfg.enabled then
        return decision.CONTINUE
    end

    local ip = ctx.request.remote_addr
    if not ip then
        return decision.CONTINUE
    end

    if ip_in_list(ip, cfg.block_ips) or ip_in_list(ip, cfg.block_cidrs) then
        ctx.enrich.reputation = { score = 100, source = "static_list" }
        ctx:trace("ip_reputation", decision.BLOCK, "IP on reputation block list")
        return decision.block(403, "Access denied")
    end

    if cfg.use_redis_feed then
        local blocked, err = redis_blocked(ip)
        if blocked == true then
            ctx.enrich.reputation = { score = 100, source = "redis_feed" }
            ctx:trace("ip_reputation", decision.BLOCK, "IP on reputation feed")
            return decision.block(403, "Access denied")
        end
        if blocked == nil and not cfg.fail_open then
            ctx:trace("ip_reputation", decision.BLOCK, "Reputation feed unavailable")
            return decision.block(503, "Service unavailable")
        end
        if err and blocked == nil then
            ngx.log(ngx.DEBUG, "badsector ip_reputation redis: ", err)
        end
    end

    ctx.enrich.reputation = { score = 0, source = "clean" }
    return decision.CONTINUE
end

return M
