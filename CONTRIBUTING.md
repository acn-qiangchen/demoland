# Contributing to Demoland

Thank you for adding a demo! This guide covers the contribution workflow.

## Workflow

```
feature/my-demo  →  main  →  staging (auto)  →  prod (manual dispatch)
```

1. Branch off `main`: `git checkout -b feature/<your-demo-name>`
2. Scaffold with `./scripts/new-demo.sh <name>`
3. Build and test locally (see [docs/getting-started.md](docs/getting-started.md))
4. Open a PR — CI will run build + lint + container scan
5. After review and merge, the app auto-deploys to staging
6. Promote to prod via **Actions → Deploy App → Run workflow**

## Code Standards

- **Dockerfiles** — use multi-stage builds; final image must be non-root
- **Terraform** — run `terraform fmt` and `terraform validate` before pushing
- **Secrets** — never commit credentials; use GitHub Secrets or a secrets manager
- **app.json** — keep it up to date (name, description, port, health endpoint)

## PR Checklist

- [ ] `app.json` is complete and valid
- [ ] `Dockerfile` builds successfully (`docker build apps/<name>`)
- [ ] App starts and health endpoint returns 200
- [ ] README in `apps/<name>/` explains what the demo does
- [ ] No secrets or credentials committed

## Getting Help

Open a [GitHub Issue](../../issues/new/choose) using the **New Demo Request** or **Bug Report** template.
