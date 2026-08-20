# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Demoland is a monorepo intended to host multiple independent demo apps plus the shared
infrastructure to deploy them. Each demo lives under `apps/<name>/` with its own container
and metadata; shared infra (VPC, cluster, ingress, DNS, monitoring) lives under `infra/` and
`platform/`.

**Important — this is an early-stage scaffold.** The README, CONTRIBUTING.md, and apps/README.md
describe the *target* architecture, but most of it does not exist yet:
- `docs/`, `scripts/`, `infra/`, `platform/`, and `.github/` are empty directories.
- The helper scripts referenced everywhere (`scripts/new-demo.sh`, `scripts/deploy.sh`,
  `scripts/destroy.sh`) have **not been written yet**.
- No CI/CD workflows, Terraform, or Dockerfiles exist yet.
- The only concrete artifacts are: the docs, `apps/_template/app.json`, and
  `llm-demo-architecture.md`.

When asked to "add a demo" or "deploy", assume you are likely *building the missing
scaffolding itself*, not running existing tooling. Verify a script/file exists before
telling the user to run it.

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
`llm-demo-architecture.md` is a **self-contained reproduction spec** for a token-streaming
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
