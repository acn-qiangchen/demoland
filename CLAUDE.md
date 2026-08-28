# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Demoland is a monorepo hosting multiple independent demo apps plus the infrastructure to
deploy them. Each demo is self-contained: application code under `apps/<name>/`, its own
Terraform under `infra/<name>/terraform/`, and its own GitHub Actions workflows (see the
Repository organization policy below). A shared platform layer (VPC, cluster, ingress, DNS,
monitoring under `platform/`) is part of the *target* design but is not built yet.

**State of the repo.** Two demos are fully built out and are the reference implementations
for the policy below: `llm-demo` (a web app — Spring Boot backend + bff + static frontend on
CloudFront/API Gateway/ALB/ECS) and `osaga-demo` (an event-driven batch pipeline — S3 →
EventBridge → Step Functions → ECS Fargate + Spring Batch). Each has real application code,
its own Terraform, and its own deploy/destroy workflows.

Parts of the *target* architecture in README / CONTRIBUTING.md / apps/README.md are still
aspirational and do **not** exist yet:
- `platform/` and `docs/` are essentially empty; there is no shared cluster/ingress/DNS —
  each demo deploys standalone to ECS Fargate.
- The generic helper scripts (`scripts/new-demo.sh`, `scripts/deploy.sh`, `scripts/destroy.sh`)
  have **not been written**. The only real script is `scripts/create-github-oidc-role.sh`.

When asked to "add a demo", copy an existing demo of the same shape (web → `llm-demo`,
batch → `osaga-demo`) rather than assuming generic scaffolding tooling exists. Verify a
script/file exists before telling the user to run it.

## Repository organization policy

Every demo is **self-contained and consistently named**. A single `<name>` (e.g. `llm-demo`,
`osaga-demo`) is used verbatim across three parallel trees, and a demo owns everything under them:

| Tree  | Path                                                          | Holds                                                                       |
| ----- | ------------------------------------------------------------ | --------------------------------------------------------------------------- |
| App   | `apps/<name>/`                                               | source, `app.json`, `README.md`, `Dockerfile`, `.dockerignore`, tests, sample data |
| Infra | `infra/<name>/terraform/`                                    | that demo's **own** self-contained Terraform module                         |
| CI/CD | `.github/workflows/<name>-deploy.yml` + `<name>-destroy.yml` | manual (`workflow_dispatch`) deploy / teardown                              |

Rules:
- **Per-demo, never shared.** `infra/` has one folder per demo (`infra/llm-demo/`,
  `infra/osaga-demo/`) — do not put one demo's infra in another's folder or in a shared module,
  and there is no shared app-infra template. Same for workflows: one deploy + one destroy per demo.
- **The name is the key.** `<name>` is the app dir, the infra dir, the workflow filename prefix,
  the Terraform `app_name` (default, which prefixes every resource), the ECR repo name, and the
  Terraform state key (`<name>/terraform.tfstate` in the shared `demoland-tfstate-<account_id>` bucket).
- **Demo-specific docs live with the demo.** Anything about one demo (quickstart, architecture
  spec, coding notes) goes under `apps/<name>/`, never at the repo root. The root keeps only
  repo-wide docs: `README.md`, `CLAUDE.md`, `CONTRIBUTING.md` (+ `apps/README.md` as the index).
- **Cross-cutting infra is not per-demo.** The shared GitHub OIDC deploy role is managed by
  `scripts/create-github-oidc-role.sh` (AWS CLI + shell, **no Terraform**). The shared Terraform
  state backend (S3 `demoland-tfstate-<account_id>` + DynamoDB `demoland-tflock`) is created
  idempotently by each deploy workflow, not checked in.
- **Demos may differ in shape, but keep the contract.** Web demos (`llm-demo`: backend + bff +
  frontend) and batch demos (`osaga-demo`: single module, no server) look different, but each
  carries a complete `app.json` — keep every field for schema consistency even when a value is
  N/A (batch jobs set `port` / `healthEndpoint` to `null` and note it in their README).

## Conventions established so far

### Per-app contract (`apps/<name>/app.json`)
Every demo carries a machine-readable `app.json` that CI/CD is meant to consume. The template
is `apps/_template/app.json`. Required fields: `name`, `description`, `version`, `maintainer`,
`port`, `healthEndpoint`, `tags`, `env[]`, and `resources` (Kubernetes-style cpu/memory
requests + limits). New demos are meant to be scaffolded by copying `apps/_template/`.

Intended per-app layout (see `apps/README.md`):
```
apps/<name>/
├── README.md          # What the demo does + how to run locally
├── app.json           # Metadata CI/CD reads
├── Dockerfile         # Multi-stage; final image must be non-root
├── .dockerignore
└── src/               # Application source
```

### LLM streaming demo spec
`apps/llm-demo/llm-demo-architecture.md` is a **self-contained reproduction spec** for a token-streaming
chat demo. If asked to build "the LLM demo", follow that file — it is authoritative. Key
constraints baked into it:
- Backend: Spring Boot 3.4 **WebFlux** (reactive) + **Spring AI 1.0.0** OpenAI starter,
  Java 17, Maven. Model `gpt-4o`.
- `POST /api/chat` returns `text/event-stream`; must set
  `produces = MediaType.TEXT_EVENT_STREAM_VALUE` or Spring buffers the whole response.
- Use `Flux.concat(tokens, doneEvent)` (not `merge`) so the `[DONE]` sentinel arrives last.
- Frontend is a single vanilla-JS `index.html` (no build step) that reads the SSE stream via
  `fetch` + `response.body.getReader()` — **not** `EventSource` (EventSource is GET-only).
- OpenAI API key comes from env `SPRING_AI_OPENAI_API_KEY`, injected in
  `application.properties`; it must never appear in frontend code.
- Spring Milestones repo must be declared in `pom.xml` for Spring AI to resolve.

## Deployment model (target design)

- Branch off `main`; PRs run build + lint + container scan (workflows TBD).
- Merge to `main` → auto-deploy to **staging** (`<app>.staging.demoland.<domain>`).
- **prod** is a manual GitHub Actions workflow dispatch (`<app>.demoland.<domain>`).
- Toolchain the design assumes: Terraform ≥1.6, Docker ≥24, kubectl ≥1.28, Helm ≥3.12, gh ≥2.

## Code standards (from CONTRIBUTING.md)

- Dockerfiles: multi-stage builds; final image runs as non-root.
- Terraform: run `terraform fmt` and `terraform validate` before pushing.
- Keep each app's `app.json` accurate (name, description, port, health endpoint).
- Secrets never committed. `.gitignore` already excludes `.env*` (except `*.example`),
  `terraform.tfvars` (except `.example`), `*.pem`, `*.key`, and `kubeconfig*`.
