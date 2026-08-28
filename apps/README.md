# Apps

Each subdirectory is an independent demo application.

## Self-contained per demo

Every demo uses one `<name>` verbatim across three parallel trees and owns everything under them:

| Tree  | Path                                                          |
| ----- | ------------------------------------------------------------ |
| App   | `apps/<name>/` (this directory)                              |
| Infra | `infra/<name>/terraform/`                                    |
| CI/CD | `.github/workflows/<name>-deploy.yml` + `<name>-destroy.yml` |

`<name>` is also the Terraform `app_name` (resource prefix), the ECR repo, and the state key
(`<name>/terraform.tfstate`). Infra is **per-demo, never shared** — there is no shared app-infra
template. Keep all demo-specific docs (quickstart, architecture spec, coding notes) **here** under
`apps/<name>/`, not at the repo root.

## Directory conventions

The exact contents vary by shape — a web demo (`llm-demo`: `backend/` + `bff/` + `frontend/`) looks
different from a batch demo (`osaga-demo`: a single module). The minimum a demo carries:

```
apps/<name>/
├── README.md          # What the demo does, how to run it locally
├── app.json           # Machine-readable metadata (CI/CD reads this)
├── Dockerfile         # Multi-stage container build (final image non-root)
├── .dockerignore
└── src/               # Application source code
```

## Adding a new demo

Copy an existing demo of the same shape (web → `llm-demo`, batch → `osaga-demo`), rename it, and
adjust `app.json`. There is no `new-demo.sh` scaffolder yet. Then add its `infra/<name>/terraform/`
and `.github/workflows/<name>-*.yml` alongside (see the existing demos for the pattern).

## Local development

Exact build/run commands are shape-specific — see each demo's own `README.md`. For a typical
single-container web demo:

```bash
# Build the container
docker build -t demoland/<name>:local apps/<name>

# Run it
docker run --rm -p 8080:8080 --env-file apps/<name>/.env.example demoland/<name>:local
```

The app will be available at http://localhost:8080. Batch demos (e.g. `osaga-demo`) run to
completion and exit rather than serving a port — follow their README instead.
