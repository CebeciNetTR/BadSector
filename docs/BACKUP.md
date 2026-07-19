# Backup & Restore

Full edge stand-up: sites + pipelines + TLS PEMs/ACME + optional secrets.

## Secrets policy

| Mode | When |
|------|------|
| **keep** (default) | Same operator moving to a new box — zip includes `secrets.env` (always has admin user/password), restore writes `data/restore/secrets.env` → merge into host `.env` |
| **rotate** | Regenerate JWT, challenge secret, engine token — **admin user/password kept** from backup for UX |
| **skip** | You copy `.env` by hand — only DB + certs restored |

Admin credentials (`BADSECTOR_ADMIN_USER` / `BADSECTOR_ADMIN_PASSWORD`) are **always** written into the zip even if “full secrets” is unchecked.

Do **not** commit backup zips or `data/restore/secrets.env` to git.

## Panel

**Backup / Restore** in the sidebar.

## CLI

```bash
# Backup
TOKEN=$(curl -sS -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"..."}' | jq -r .token)
BADSECTOR_BACKUP_TOKEN=$TOKEN ./scripts/backup.sh

# Restore on new box (stack already up with temporary .env)
BADSECTOR_BACKUP_TOKEN=$TOKEN ./scripts/restore.sh ./badsector-backup-....zip --keep-secrets
# merge data/restore/secrets.env into .env
docker compose up -d
docker compose restart haproxy engine api watcher
```

## Zip layout

```
meta.json
db.json                 # sites, policies, pipeline_stages, certificates
secrets.env             # optional
certs/...               # haproxy + private + acme
challenge/template.html # optional
```

Redis bans / attack mode are **not** included (ephemeral).
