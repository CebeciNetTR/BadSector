# Contributing to BadSector

Thank you for contributing to BadSector. This project prioritizes **performance** and **code quality** over feature count.

## Development Setup

```bash
# Go services
go mod download

# UI
cd ui && npm install

# Full stack (Linux/macOS/WSL2)
docker compose up -d --build
./scripts/smoke-test.sh
```

See [docs/TEST_ENV.md](docs/TEST_ENV.md) for the first test environment setup.

## Architecture Rules

1. **Heavy work goes late** in the pipeline — cheap filters first.
2. **No duplicate enrichment** — use `ctx:ensure()` for shared lookups.
3. **Modules are independent** — never import another module directly.
4. **Terminal decisions stop the pipeline** — no exceptions.
5. **No nginx syntax in user config** — policies only.

## Adding a Module

See [docs/MODULES.md](docs/MODULES.md). Built-in modules live in `engine/lib/badsector/modules/`. Third-party plugins live in `plugins/`.

## Pull Requests

- One logical change per PR
- Include tests where behavior is non-trivial
- Document new modules and API endpoints in `docs/`
- Update [CHANGELOG.md](../CHANGELOG.md) for user-visible changes
- Update [README.md](../README.md) development status table when completing a feature
- Benchmark hot-path changes when touching the engine

## Code Style

- **Lua**: follow existing module structure, precompile in `init()`
- **Go**: standard `gofmt`, minimal abstractions
- **TypeScript**: strict mode, functional React components

## Performance Budget

Module execution target: **< 1ms**. If your module cannot meet this, document why and default to disabled.
