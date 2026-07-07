# Dashboard (UI)

The BadSector dashboard is a React + TypeScript app in `ui/`. Users configure behavior through visual forms — no nginx syntax is exposed.

## Development

```bash
cd ui
npm install
npm run dev    # http://localhost:3000
```

Vite proxies `/api` requests to `http://localhost:8080` during development.

Environment variable:

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_URL` | `/api/v1` | API base path |

## Pages

| Route | Status | Description |
|-------|--------|-------------|
| `/` | **Done** | Live metrics from Redis |
| `/sites` | **Done** | Site CRUD, upstream URL, pipeline summary |
| `/rate-limits` | **Done** | Rate limit rule management |
| `/policies` | **Done** | Policy CRUD with condition/action builder |
| `/security-modules` | **Done** | ASN, headers, burst, challenges |
| `/managed-waf` | **Done** | Coraza WAF module config (mode, paranoia, exclusions) |
| `/pipeline` | **Done** | Drag-and-drop module reorder, enable/disable, add modules |
| `/trace` | **Done** | Live request trace with explainability panel |
| `/modules` | Planned | Module enable/disable per site |
| `/certificates` | Done | Let's Encrypt TLS management |
| `/settings` | Planned | Global platform settings |

## Sites (`/sites`)

Manage hostname-bound sites. Each site has its own pipeline, policies, and rate limits.

**Features:**
- List sites with status, hostnames, last updated
- Create new site (assigns default pipeline via API)
- Edit name, hostnames, enabled state, debug trace
- Delete with confirmation modal
- Link to Rate Limits page for selected site

**Form fields:**

| Field | Maps to |
|-------|---------|
| Site adı | `site.name` |
| Hostnames | `site.hosts[]` |
| Backend URL | `reverse_proxy.config.backend_url` |
| Durum | `site.enabled` |
| Debug trace | `site.settings.debug_trace` |

**Pipeline summary:** Below the form, shows ordered modules with active/inactive status.

## Policies (`/policies`)

Configure the `policies` pipeline module per site.

**Features:**
- Site selector (supports `?site={id}` query param)
- Policy list with priority, conditions summary, actions summary
- Policy editor: name, priority, conditions (AND/OR), actions
- Enable/disable toggle per policy (immediate save)
- Delete with confirmation modal
- Save → API + runtime reload

**Query param:**

```
/policies?site=abc-123
```

## Pipeline (`/pipeline`)

Configure module order per site with drag-and-drop.

**Features:**
- Site selector (supports `?site={id}` query param)
- Drag-and-drop reorder (HTML5 native)
- Enable/disable toggle per module
- Add modules from catalog panel
- Remove modules (except `reverse_proxy`)
- `reverse_proxy` locked as last module
- Save & apply → `PUT /pipeline` + runtime reload
- Reset to last saved state

**Query param:**

```
/pipeline?site=abc-123
```

## Managed WAF (`/managed-waf`)

Configure the `managed_waf` Coraza pipeline module.

**Features:**
- Site selector
- Enable/disable module
- Ruleset, paranoia level, block/detect mode
- Exclude paths, audit logging, rules directory
- Save → updates pipeline stage + runtime reload

## Rate Limits (`/rate-limits`)

Configure the `rate_limiter` pipeline module per site.

**Features:**
- Site selector (supports `?site={id}` query param from Sites page)
- Module settings: enabled, Redis, fail mode
- Rule list with enable/disable toggle
- Rule editor: name, key strategy, limit, burst, window, paths, HTTP methods
- Save & apply → `PUT /rate-limits` + `POST /runtime/reload`
- Unsaved changes indicator

**Query param:**

```
/rate-limits?site=abc-123
```

Pre-selects the site when navigating from the Sites table.

## Design Principles

1. **Policy-driven** — Users never edit nginx or Lua directly
2. **Explainability** — Trace page shows why requests were blocked
3. **Live reload** — Save triggers runtime regeneration, no nginx reload
4. **Turkish UI labels** — User-facing labels in Turkish

## Component Structure

```
ui/src/
├── api/client.ts          # API fetch wrapper
├── types/
│   ├── site.ts            # Site types and helpers
│   └── rateLimit.ts       # Rate limit types
├── components/
│   ├── sites/             # SiteList, SiteForm, DeleteSiteModal
│   └── rateLimit/         # RuleList, RuleForm, ModuleSettings
└── pages/
    ├── Sites.tsx
    └── RateLimits.tsx
```

## Planned UI Work

- Visual policy editor with condition/action builder
- Drag-and-drop pipeline reordering
- Live request trace from engine (WebSocket or polling)
- Upstream/backend URL editor in Sites form
