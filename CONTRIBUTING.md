# Contributing to Demoland

Thank you for adding a demo! This guide covers the contribution workflow.

## Workflow

```
feature/my-demo  →  main  →  staging (auto)  →  prod (manual dispatch)
```

1. Branch off `main`: `git checkout -b feature/<your-demo-name>`
2. Copy an existing demo of the same shape (web → `apps/llm-demo`, batch → `apps/osaga-demo`)
   — there is no `new-demo.sh` scaffolder yet
3. Build and test locally (see the demo's own `README.md`)
4. Open a PR — CI will run build + lint + container scan
5. After review and merge, the app auto-deploys to staging
6. Promote to prod via **Actions → Deploy App → Run workflow**

## Repository layout & naming

Every demo is **self-contained** and uses one `<name>` verbatim across three parallel trees:

| Tree  | Path                                                          |
| ----- | ------------------------------------------------------------ |
| App   | `apps/<name>/`                                               |
| Infra | `infra/<name>/terraform/`                                    |
| CI/CD | `.github/workflows/<name>-deploy.yml` + `<name>-destroy.yml` |

- **Per-demo, never shared** — one infra folder and one deploy/destroy workflow pair per demo;
  don't reach into another demo's folder or a shared module.
- **The name is the key** — the same `<name>` is the app dir, the infra dir, the workflow prefix,
  the Terraform `app_name` (which prefixes every resource), the ECR repo, and the Terraform
  state key (`<name>/terraform.tfstate`).
- **Demo docs live with the demo** — put anything demo-specific (quickstart, architecture spec,
  coding notes) under `apps/<name>/`, not at the repo root.
- **Demos may differ in shape** — web (`llm-demo`: backend + bff + frontend) vs batch
  (`osaga-demo`: single module, no server) — but each still carries a complete `app.json`.

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
