# llm-demo-bff

A **Backend-For-Frontend (BFF)** layer that sits between the web frontend and the LLM backend.
The browser now calls the BFF, and the BFF relays to the backend using a blocking
`RestTemplate` backed by **Apache HttpClient 5**.

```
browser (index.html)  ->  bff (:8081)  ->  backend (:8080, Spring AI + OpenAI)
```

## Endpoints (mirror the backend contract, so the frontend needs no path changes)

| Method | Path             | Relays to                    | Response            |
|--------|------------------|------------------------------|---------------------|
| POST   | `/api/chat`      | backend `POST /api/chat`     | `text/event-stream` (streamed through) |
| POST   | `/api/chat/rest` | backend `POST /api/chat/rest`| `application/json`  |
| GET    | `/health`        | —                            | `ok`                |

The SSE path streams the upstream response chunk-by-chunk (no buffering), so tokens still reach
the browser progressively even though `RestTemplate` is a blocking client.

## Configuration (`application.yaml`)

All timeouts are placeholders in milliseconds — tune per environment (env-var overrides shown):

| Key                                 | Env var                              | Default | Meaning |
|-------------------------------------|--------------------------------------|---------|---------|
| `llm.service.base-url`              | `LLM_SERVICE_BASE_URL`               | `http://localhost:8080` | Backend URL |
| `llm.http.connect-timeout`          | `LLM_HTTP_CONNECT_TIMEOUT`           | `5000`  | TCP connect |
| `llm.http.read-timeout`             | `LLM_HTTP_READ_TIMEOUT`              | `60000` | Socket read (per-read; for SSE = max gap between tokens) |
| `llm.http.connection-request-timeout` | `LLM_HTTP_CONNECTION_REQUEST_TIMEOUT` | `5000` | Wait for a pooled connection |
| `spring.mvc.async.request-timeout`  | `BFF_ASYNC_REQUEST_TIMEOUT`          | `300000`| Max lifetime of a relayed SSE stream |

## Run locally

```bash
# 1. start the backend (port 8080) — see ../backend/README.md
# 2. start the BFF (port 8081)
mvn spring-boot:run
# 3. point the frontend at :8081 (it uses relative /api/* paths, so serve index.html
#    behind the same origin as the BFF, or set the origin accordingly)
```

## Deployment note

In the deployed model (CloudFront → ALB for `/api/*`), the ALB should now target the **BFF**, and
the BFF reaches the backend via `LLM_SERVICE_BASE_URL`. The backend no longer needs to be exposed
to the public `/api/*` path directly. Terraform wiring for this is a follow-up.
