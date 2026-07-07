# Rate Limiter Module

Distributed rate limiting with Redis primary store and OpenResty shared dict fallback.

## Algorithm

Fixed-window counter with optional burst allowance:

```
effective_limit = limit + burst
count = INCR key (atomic with EXPIRE on first hit)
allowed = count <= effective_limit
```

Redis uses a Lua script for atomic `INCR` + `EXPIRE`. Shared dict uses `ngx.shared.badsector_counters:incr(key, 1, 0, window)`.

## Configuration

```json
{
  "use_redis": true,
  "fail_mode": "open",
  "redis": {
    "host": "redis",
    "port": 6379,
    "timeout": 100
  },
  "rules": [
    {
      "id": "rl-global-ip",
      "name": "Global per-IP limit",
      "key_by": "ip",
      "limit": 100,
      "burst": 20,
      "window": "1m",
      "paths": ["/*"]
    }
  ]
}
```

### Key Strategies (`key_by`)

| Value | Key basis |
|-------|-----------|
| `ip` | Client IP |
| `ip_path` | IP + request path |
| `host` | Host header |
| `global` | Site-wide single counter |
| `header` | Named header value |
| `cookie` | Named cookie value |

### Window Format

`60`, `"60"`, `"60s"`, `"1m"`, `"1h"`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BADSECTOR_REDIS_HOST` | `127.0.0.1` | Redis host |
| `BADSECTOR_REDIS_PORT` | `6379` | Redis port |
| `BADSECTOR_REDIS_TIMEOUT` | `100` | Connect timeout (ms) |
| `BADSECTOR_REDIS_PASSWORD` | — | Optional auth |

## Response Headers (429)

- `Retry-After`
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

## Policy Integration

After rate limiter runs, these are available for policy conditions:

- `ctx.enrich.rate` — `{ count, limit, remaining, rule_id, ... }`
- `ctx:get_var("rate_count")` — current counter value

Condition example:

```json
{
  "type": "rate",
  "operator": "gt",
  "value": 50
}
```

## Fail Modes

| Mode | Behavior when Redis and shared dict both fail |
|------|-----------------------------------------------|
| `open` | Allow request (availability) |
| `closed` | Return 429 (strict security) |

Production deployments should always run Redis with `fail_mode: closed` if rate limiting is critical.

## Pipeline Placement

Place **after** cheap filters (access lists, geoip) and **before** expensive modules (WAF, challenges):

```
Access Lists → GeoIP → Policies → Rate Limiter → Challenge → WAF → Cache → Proxy
```
