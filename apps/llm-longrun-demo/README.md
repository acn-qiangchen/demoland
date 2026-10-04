# llm-longrun-demo

**One problem, two fixes.** A long-running `gpt-4o` call takes longer than a request timeout allows.
This demo shows that problem and the two standard ways to solve it, all behind **one backend, one BFF,
one frontend and one Terraform stack**:

- **Sync (blocking)** — *the problem.* One request held open for the whole generation. On the deployed
  path it trips the ALB idle timeout and the client gets a **504**.
- **SSE streaming** — *fix 1.* Tokens stream back as `text/event-stream`; each byte resets the ALB idle
  timer, so the connection survives and you watch the model "think" in real time.
- **Async request + poll** — *fix 2.* `POST` returns a **job id** in <1s, then the browser polls for the
  result. Nothing is held open long enough to time out. The job store switches between **ElastiCache
  Redis** and **DynamoDB** per request.

The merged demo is built on the same stack throughout: Spring Boot 3.4.1 **WebFlux** + **Spring AI
1.0.0** (`gpt-4o`), a thin blocking **BFF** relay, and a vanilla-JS frontend.

> The key insight: the three paths conflict on exactly one setting — the ALB `idle_timeout`. A single
> **moderate default (20s)** demonstrates all three at once: sync trips it, SSE's token-per-few-hundred-ms
> flow resets it, and async's sub-second submit never reaches it.

## Shape

```
                                   ┌─ SSE  (POST /api/chat, text/event-stream)
browser ──▶ bff (8081) ──▶ backend (8080) ──▶ OpenAI (gpt-4o)
                                   ├─ Sync (POST /api/chat/sync, blocking)
                                   └─ Async (POST /api/chat/async → job)
                                              │
                                     ┌────────┴────────┐
                                     ▼                 ▼
                               ElastiCache Redis   DynamoDB
```

- **backend/** — Spring Boot WebFlux + Spring AI. One `OpenAiService` with `streamResponse()`
  (`Flux<String>`, for SSE) and `getFullResponse()` (`Mono<String>`, for sync + the async job). Owns
  the job lifecycle and the two stores.
- **bff/** — Spring MVC (servlet, blocking) relay. Streams `/api/chat` through byte-by-byte via
  `StreamingResponseBody`; passes the sync/async/poll JSON endpoints straight through.
- **frontend/** — single vanilla-JS `index.html` with a **three-way mode selector** (sync / sse /
  async), plus `architecture.html` (the "problem → two fixes" explainer). No build step.

## API

| Method & path                                | Body / params             | Returns                                                           | Role     |
| -------------------------------------------- | ------------------------- | ---------------------------------------------------------------- | -------- |
| `POST /api/chat`                             | `{ "message" }`           | `text/event-stream` — `token` events then `[DONE]`               | Fix 1    |
| `POST /api/chat/sync`                        | `{ "message" }`           | `200 { "content" }` — blocks until done                          | Problem  |
| `POST /api/chat/async`                       | `{ "message", "store" }`  | `202 { "jobId", "store", "status" }` — returns immediately       | Fix 2    |
| `GET /api/jobs/{jobId}?store=redis\|dynamo`  | path `jobId`, query `store` | `200 { jobId, status, result, error, store, createdAt, completedAt }` or `404` | Fix 2 |
| `GET /health`                                | —                         | `ok`                                                             | health   |

`store` accepts `redis` (default) or `dynamo`. Job status flows `PENDING → PROCESSING → COMPLETED`
(or `FAILED`). Jobs carry a 1-hour TTL in both stores so demo data self-cleans. SSE tokens are sent
JSON-encoded (`{"content":"..."}`) so leading spaces and newlines survive the SSE text protocol.

See **`llm-longrun-demo-architecture.md`** for the authoritative reproduction spec, including the SSE
constraints that must hold for streaming to work end-to-end.

## Run locally

The backend needs a reachable Redis for the redis path and AWS credentials + a DynamoDB table for the
dynamo path. The simplest local loop uses Redis via Docker and the `redis` store toggle:

```bash
# 1) Redis
docker run -p 6379:6379 redis:7

# 2) backend (port 8080)
cd backend
SPRING_AI_OPENAI_API_KEY=sk-... mvn spring-boot:run

# 3) bff (port 8081)
cd ../bff
mvn spring-boot:run

# 4) open the frontend (any static server), e.g.
cd ../frontend && python3 -m http.server 8000
# then browse http://localhost:8000 — it calls the bff at :8081 in the deployed stack;
# for local use, point the /api/* calls at http://localhost:8081 or run behind a proxy.
```

Exercise all three modes from the UI: **sync** (with a long prompt, watch it hold the connection —
and 504 past the ALB idle timeout once deployed), **sse** (tokens stream progressively, `[DONE]`
last), **async** (202 + jobId, polling flips PENDING→PROCESSING→COMPLETED; toggle redis vs dynamo).

For the `dynamo` toggle locally, set `JOBS_TABLE_NAME` + `AWS_REGION` and have credentials for a
DynamoDB table with primary key `jobId` (String) and TTL on attribute `ttl`.

## Deploy

Manual GitHub Actions: **llm-longrun-demo deploy** / **llm-longrun-demo destroy** (workflow_dispatch).
Infra lives in `infra/llm-longrun-demo/terraform/` and provisions ElastiCache Redis + a DynamoDB table
alongside the ECS/ALB/API Gateway/CloudFront stack. API Gateway uses **STREAM** mode on `/api/chat`
(for SSE) and a greedy **BUFFERED** proxy for everything else; the ALB `idle_timeout` defaults to **20s**
(`var.alb_idle_timeout`) so the sync baseline visibly trips it while SSE and async sail under it.
