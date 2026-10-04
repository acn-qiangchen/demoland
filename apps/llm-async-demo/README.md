# llm-async-demo

An asynchronous **request-and-forget + poll** take on `llm-demo`. Instead of streaming tokens over
SSE, the client starts a long-running LLM job, gets a **job id** back immediately, and then **polls**
for the result. The job state is kept in a **switchable store** — AWS **ElastiCache Redis** or
**DynamoDB** — chosen per request from the web UI. The poll interval is adjustable in the UI too.

Same model backend as `llm-demo` (Spring Boot WebFlux + Spring AI, `gpt-4o`); only the client-side
contract differs.

## Shape

```
browser ──▶ bff (8081) ──▶ backend (8080) ──▶ OpenAI
                                   │
                          ┌────────┴────────┐
                          ▼                 ▼
                    ElastiCache Redis   DynamoDB
```

- **backend/** — Spring Boot WebFlux + Spring AI. Owns the job lifecycle and the two stores.
- **bff/** — relays the two JSON endpoints to the frontend (mirrors `llm-demo`'s bff shape).
- **frontend/** — single vanilla-JS `index.html` (store toggle + poll-interval slider, no build step).

## API

| Method & path                         | Body / params                       | Returns                                                            |
| ------------------------------------- | ----------------------------------- | ----------------------------------------------------------------- |
| `POST /api/chat/async`                | `{ "message", "store" }`            | `202 { "jobId", "store", "status" }` — returns immediately        |
| `GET /api/jobs/{jobId}?store=redis\|dynamo` | path `jobId`, query `store`    | `200 { jobId, status, result, error, store, createdAt, completedAt }` or `404` |
| `GET /health`                         | —                                   | `ok`                                                              |

`store` accepts `redis` (default) or `dynamo`. Job status flows `PENDING → PROCESSING → COMPLETED`
(or `FAILED`). Jobs carry a 1-hour TTL in both stores so demo data self-cleans.

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
# for local use, point START_URL / jobUrl at http://localhost:8081 or run behind a proxy.
```

For the `dynamo` toggle locally, set `JOBS_TABLE_NAME` + `AWS_REGION` and have credentials for a
DynamoDB table with primary key `jobId` (String) and TTL on attribute `ttl`.

## Deploy

Manual GitHub Actions: **llm-async-demo deploy** / **llm-async-demo destroy** (workflow_dispatch).
Infra lives in `infra/llm-async-demo/terraform/` and provisions ElastiCache Redis + a DynamoDB table
alongside the `llm-demo`-style ECS/ALB/API Gateway/CloudFront stack.
