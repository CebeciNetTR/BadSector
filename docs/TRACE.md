# Live Request Trace

Cloudflare-style explainability: every request records pipeline steps, timing, and the final decision.

## Enable tracing

Set per-site in `settings`:

```json
{
  "live_trace": true,
  "debug_trace": false
}
```

| Setting | Effect |
|---------|--------|
| `live_trace` | Buffer recent traces in Redis for the dashboard |
| `debug_trace` | Add `X-BadSector-Trace` response header (JSON steps) |

Default seed site enables `live_trace`.

## Engine behavior

After pipeline execution, `badsector.trace` writes a JSON record to Redis:

- Key: `badsector:trace:{site_id}`
- Structure: LPUSH + LTRIM (default 100 entries, TTL 1 hour)
- Env: `BADSECTOR_TRACE_BUFFER_SIZE`, `BADSECTOR_TRACE_TTL`

Each record includes request metadata, `steps[]` from `ctx.trace`, final decision, and total duration.

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/sites/:id/traces?limit=50` | Recent traces (newest first) |

Requires JWT when `BADSECTOR_AUTH_DISABLED` is not set.

## UI

`/trace` — site selector, 2s polling, step-by-step explainability panel.

Send traffic to the engine (port 9080) with a matching Host header to populate traces.
