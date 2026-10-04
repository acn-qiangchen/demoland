# LLM Long-Running Demo — Architecture & Reconstruction Spec

> **Purpose of this document**
> This is a self-contained specification for `llm-longrun-demo`. An AI agent reading this file should be
> able to reproduce the working demo from scratch. It is the **authoritative** source for the demo's
> contract and, in particular, the SSE constraints in §8 — treat those as hard requirements.

---

## 1. What the Demo Does

A single-page web UI lets a user type a prompt and pick one of **three modes** that all hit the same
Spring Boot backend and the same `gpt-4o` model:

1. **Sync (blocking)** — *the problem.* `POST /api/chat/sync` blocks until the whole answer is
   generated, then returns one JSON body. On the deployed path the connection sits idle (no bytes) and
   the **ALB idle timeout cuts it → 504**.
2. **SSE streaming** — *fix 1.* `POST /api/chat` returns `text/event-stream`; each token is flushed as
   it generates. Every byte resets the ALB idle timer, so the connection survives and tokens appear
   live in the UI.
3. **Async request + poll** — *fix 2.* `POST /api/chat/async` writes a job to a store, runs the LLM
   call in the background, and returns `202 { jobId }` immediately. The browser polls
   `GET /api/jobs/{id}` until `COMPLETED`. The job store switches between **Redis** and **DynamoDB**
   per request.

The three paths conflict on exactly one setting — the ALB `idle_timeout` — and a single moderate
default (**20s**) demonstrates all three at once.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Browser  (index.html — vanilla JS, 3-way mode selector)     │
│   sync  : fetch POST /api/chat/sync → await response.json()  │
│   sse   : fetch POST /api/chat → body.getReader() (SSE)      │
│   async : POST /api/chat/async → poll GET /api/jobs/{id}     │
└───────────────────────────┬──────────────────────────────────┘
                            │  CloudFront → API Gateway → ALB
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  BFF  (Spring MVC, servlet/blocking, :8081)                  │
│   /api/chat       → StreamingResponseBody (byte-by-byte SSE)  │
│   /api/chat/sync  → RestTemplate passthrough                 │
│   /api/chat/async → RestTemplate passthrough                 │
│   /api/jobs/{id}  → RestTemplate passthrough                 │
└───────────────────────────┬──────────────────────────────────┘
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  Backend  (Spring Boot 3.4.1 WebFlux, reactive, :8080)      │
│   ChatController (one controller, all 4 endpoints)           │
│    └─ OpenAiService                                          │
│        ├─ streamResponse() → Flux<String>  (SSE)            │
│        └─ getFullResponse() → Mono<String> (sync + job)     │
│   JobStoreResolver → RedisJobStore | DynamoJobStore         │
└───────────────┬───────────────────────────┬──────────────────┘
                ▼                            ▼
          ElastiCache Redis           DynamoDB (TTL)
                            │
                            ▼  OpenAI API — gpt-4o, stream:true
```

---

## 3. Technology Stack

| Layer | Technology | Version |
|---|---|---|
| Backend | Spring Boot WebFlux (reactive, Netty) | 3.4.1 / Java 17 |
| LLM | Spring AI OpenAI starter (`ChatClient`) | 1.0.0 |
| Job stores | Spring Data Redis Reactive + AWS SDK v2 DynamoDB async | — |
| BFF | Spring Boot MVC (servlet, Tomcat) + Apache HttpClient 5 | 3.4.1 / Java 17 |
| Frontend | Vanilla JS + HTML (no build step) | — |
| Model | gpt-4o | — |

---

## 4. Project Structure

```
apps/llm-longrun-demo/
├── backend/   src/main/java/com/demo/longrun/
│   ├── LlmLongrunDemoApplication.java   @SpringBootApplication
│   ├── ChatController.java              all 4 endpoints (SSE + sync + async + poll)
│   ├── OpenAiService.java               streamResponse() + getFullResponse()
│   ├── ChatRequest.java                 record { message, store }
│   ├── Job.java / JobStatus.java        job model + lifecycle
│   ├── JobStore.java / JobStoreResolver.java
│   ├── RedisJobStore.java / DynamoJobStore.java / DynamoConfig.java
│   └── HealthController.java            GET /health → "ok"
├── bff/       src/main/java/com/demo/bff/   RelayController + RestClientConfig + ...
└── frontend/  index.html (3-way UI) + architecture.html (explainer)
```

---

## 5. Unified API Contract (`/api`, CORS `*`)

| Endpoint | Method | Behavior |
| --- | --- | --- |
| `/api/chat` | POST | SSE `text/event-stream`, `Flux<ServerSentEvent>` + `[DONE]` |
| `/api/chat/sync` | POST | Blocking `Mono<FullResponse>` `{ "content" }` |
| `/api/chat/async` | POST | `202 { jobId, store, status }`, runs LLM in background |
| `/api/jobs/{id}?store=redis\|dynamo` | GET | Poll job → `Job` or `404` |
| `/health` | GET | `"ok"` |

SSE event framing (tokens JSON-encoded so whitespace/newlines survive):
```
event: token
data: {"content":"Hello"}

event: done
data: [DONE]
```

---

## 6. Configuration (`application.properties`)

```properties
spring.ai.openai.api-key=${SPRING_AI_OPENAI_API_KEY:your-api-key-here}
spring.ai.openai.chat.options.model=gpt-4o
spring.ai.openai.chat.options.max-tokens=2048
server.port=8080
spring.data.redis.host=${REDIS_HOST:localhost}
spring.data.redis.port=${REDIS_PORT:6379}
jobs.table-name=${JOBS_TABLE_NAME:llm-longrun-demo-jobs}
aws.region=${AWS_REGION:us-east-1}
```

The BFF `application.yaml` keeps `read-timeout: 60000` — deliberately **above** the ALB idle timeout so
the ALB is the binding limit on the sync path (the bff→backend hop does not traverse the ALB).

---

## 7. Deployment notes (why a single idle timeout works)

- **ALB `idle_timeout` default = 20s** (`var.alb_idle_timeout`). Sits below the API Gateway BUFFERED cap
  (29s) and CloudFront origin read (60s). Sync (no bytes) is cut here; SSE (byte every few hundred ms)
  resets it; async (sub-second submit) never reaches it.
- **API Gateway**: an explicit `/api/chat` POST resource uses `response_transfer_mode = STREAM`
  (`timeout_milliseconds = 900000`) for SSE; a greedy `/api/{proxy+}` ANY in default **BUFFERED** mode
  covers `/api/chat/sync`, `/api/chat/async`, `/api/jobs/{id}`. Routing precedence sends the exact
  `/api/chat` to the explicit resource and everything deeper to the proxy.
- Regional endpoint (behind CloudFront); edge-optimized's 30s idle would cut SSE streams.

---

## 8. SSE constraints (hard requirements — carry these verbatim)

1. **Do not use `EventSource`** for the SSE client — it only supports GET. Use `fetch` +
   `response.body.getReader()`.
2. **Spring AI version must be `1.0.0`** (or later). Earlier milestones have different artifact IDs.
3. **The Spring Milestones repository must be declared** in `pom.xml` or Maven will not resolve Spring
   AI artifacts.
4. **API key must never appear in frontend code.** It lives in `application.properties` and is injected
   via env `SPRING_AI_OPENAI_API_KEY`.
5. **`@CrossOrigin("*")`** on the controller is required for cross-origin requests. Restrict in prod.
6. **`Flux.concat(tokens, doneEvent)`** — the `[DONE]` sentinel must come after all tokens, not in
   parallel. Use `concat`, not `merge`.
7. **`produces = MediaType.TEXT_EVENT_STREAM_VALUE`** is mandatory on `/api/chat`. Without it, Spring
   buffers the entire response before sending.
8. **Tokens are JSON-encoded** (`TokenChunk` → `{"content":"..."}`). Sending the raw string breaks on
   the SSE text protocol: `data:` strips one leading space and splits embedded newlines across multiple
   `data:` lines. The browser must `JSON.parse(data).content` to recover the exact text.

Additional (merge-specific) notes:
- The BFF SSE relay uses `StreamingResponseBody`, reading the upstream `InputStream` in 512-byte chunks
  and `flush()`ing each — a blocking servlet stack can still pass SSE through in real time this way. On
  upstream failure it emits an `event: error` frame (the 200/headers are already committed, so it can't
  become a 504 on the stream path).
- The sync baseline and the async background job share `OpenAiService.getFullResponse()`; only the
  wrapper (client-blocking vs background-job) differs.
