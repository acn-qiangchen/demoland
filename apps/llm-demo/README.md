# llm-demo

A token-streaming chat demo. You type a prompt; the browser POSTs it to a Spring Boot **WebFlux**
backend, which calls the OpenAI API with streaming enabled and pipes each token back to the
browser as a Server-Sent Event (SSE). Tokens appear character-by-character in real time. A metrics
strip shows time-to-first-byte, total time, and token count.

Authoritative spec: [`llm-demo-architecture.md`](../../llm-demo-architecture.md).

## Layout

```
apps/llm-demo/
├── app.json                 # CI/CD metadata
├── backend/                 # Spring Boot 3.4 WebFlux + Spring AI 1.0.0 (Java 17, Maven)
│   ├── pom.xml
│   ├── Dockerfile           # multi-stage, non-root runtime
│   └── src/main/...         # ChatController (POST /api/chat SSE), OpenAiService, /health
└── frontend/
    └── index.html           # single vanilla-JS file, no build step
```

## Run locally

```bash
# 1. Backend
cd apps/llm-demo/backend
export SPRING_AI_OPENAI_API_KEY=sk-...
mvn spring-boot:run          # starts on http://localhost:8080

# 2. Frontend — served relative to the backend behind CloudFront in prod.
#    For local dev, either open index.html and temporarily point API_URL at
#    http://localhost:8080/api/chat, or serve it from any static server.
```

Quick backend smoke test:

```bash
curl localhost:8080/health                       # -> ok
curl -N -X POST localhost:8080/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"hi"}'                           # streams event: token ... event: done [DONE]
```

> Note: `frontend/index.html` uses a **relative** `API_URL = '/api/chat'` so it works behind
> CloudFront (S3 default origin + ALB `/api/*` origin) with no CORS. For a pure-local run you can
> temporarily change that constant to the absolute backend URL.

## How it deploys

Deployment is fully driven by GitHub Actions (manual `workflow_dispatch`) onto AWS:

- **Backend** → container on **ECS Fargate**, fronted by an internet-facing **ALB** (idle timeout 300s
  for SSE), image stored in **ECR**.
- **Frontend** → `index.html` in a private **S3** bucket served via **CloudFront** (default origin).
- **Routing** → one CloudFront distribution: default `/*` → S3, ordered `/api/*` → ALB. The browser
  calls the relative `/api/chat`, so there is no CORS and no custom domain needed.
- **OpenAI key** → GitHub repo secret `SPRING_AI_OPENAI_API_KEY` → AWS Secrets Manager →
  injected into the ECS task as an env var. It never appears in workflow inputs or logs.

Infra is Terraform in [`infra/app-template/terraform/`](../../infra/app-template/terraform/),
parameterized by `app_name` (default `llm-demo`).

Workflows:
- **`.github/workflows/llm-demo-deploy.yml`** — bootstraps TF state, builds + pushes the image,
  applies Terraform, uploads the frontend, and prints the CloudFront URL.
- **`.github/workflows/llm-demo-destroy.yml`** — tears everything down.

Both take AWS `account_id` / `access_key_id` / `secret_access_key` / `region` as dispatch inputs.
