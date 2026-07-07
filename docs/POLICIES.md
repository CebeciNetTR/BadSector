# Policy Engine

Policies are the primary user-facing configuration primitive. Users never write nginx syntax.

## Structure

```json
{
  "id": "pol-014",
  "name": "Block admin from non-EU",
  "site_id": "site-001",
  "priority": 100,
  "enabled": true,
  "conditions": {
    "operator": "and",
    "rules": [
      { "type": "path", "operator": "prefix", "value": "/admin" },
      {
        "operator": "or",
        "rules": [
          { "type": "country", "operator": "not_in", "value": ["DE", "FR", "NL"] },
          { "type": "trusted_bot", "operator": "eq", "value": false }
        ]
      }
    ]
  },
  "actions": [
    { "type": "return_444" },
    { "type": "log", "level": "warn", "message": "Admin access blocked: non-EU" },
    { "type": "tag", "value": "geo-block" }
  ]
}
```

## Condition Operators

| Operator | Applies to | Description |
|----------|------------|-------------|
| `eq` | all | Exact match |
| `neq` | all | Not equal |
| `contains` | string | Substring |
| `not_contains` | string | Negated substring |
| `prefix` | path | Path prefix |
| `suffix` | path | Path suffix |
| `regex` | string | Regular expression (precompiled) |
| `in` | set | Value in list |
| `not_in` | set | Value not in list |
| `gt`, `gte`, `lt`, `lte` | numeric | Comparison |
| `exists` | header/cookie | Presence check |
| `missing` | header/cookie | Absence check |

## Action Reference

| Action | Parameters | Terminal |
|--------|------------|----------|
| `allow` | — | Yes |
| `continue` | — | No |
| `return_444` | — | Yes |
| `block` | `status`, `body` | Yes |
| `redirect` | `url`, `status` | Yes |
| `js_challenge` | `difficulty` | Yes |
| `cookie_challenge` | `ttl` | Yes |
| `captcha` | `provider` | Yes |
| `cache` | `ttl`, `key` | Yes |
| `rate_limit` | `limit`, `window` | Yes |
| `log` | `level`, `message` | No |
| `tag` | `value` | No |
| `skip_module` | `module` | No |
| `skip_remaining` | — | Yes (jumps to reverse_proxy) |

Actions execute in order. First terminal action wins.

## Compilation

The API compiles policies to an optimized evaluation tree:

```
1. Group by site
2. Sort by priority (ascending)
3. Index conditions by cheap checks first (method, path prefix)
4. Defer expensive checks (rate, fingerprint) to leaf nodes
5. Emit runtime JSON consumed by engine policies module
```

## Visual Editor Mapping

Dashboard nodes map 1:1 to policy JSON:

```
[Condition: Path starts with /admin]
           │
           ▼
[Condition: Country NOT IN EU]
           │
           ▼
[Action: Return 444]
```

## Live Reload

1. User saves policy in UI (Policies page)
2. API validates against JSON Schema
3. API stores in PostgreSQL, emits change event
4. Worker recompiles site policy bundle
5. Engine `policies` module calls `reload()` — atomic swap in shared memory
6. No nginx reload

## Explainability

When a policy matches, trace includes:

```json
{
  "module": "policies",
  "decision": "RETURN_444",
  "ms": 0.08,
  "detail": "Policy #14 'Block admin from non-EU' matched",
  "policy_id": "pol-014",
  "matched_conditions": ["path:/admin", "country:not_in:EU"]
}
```
