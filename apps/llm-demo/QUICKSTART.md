# Quick Start — llm-demo

A copy-paste guide to **run the streaming chat demo locally** and **deploy/tear it down on AWS**.
For the architecture and why things are wired this way, see
[`README.md`](README.md) and [`llm-demo-architecture.md`](llm-demo-architecture.md).

You need an **OpenAI API key** (starts with `sk-...`) for both paths.

---

## A. Run locally

The local stack is three pieces: the **backend** LLM service (`:8080`), the **BFF** relay
(`:8081`) that the web frontend talks to, and the static **frontend**.

```
browser (index.html)  ->  bff (:8081)  ->  backend (:8080, Spring AI + OpenAI)
```

**Prereqs:** JDK 17, Maven 3.9+ (check: `java -version` → 17, `mvn -v`), and two free terminals
(one each for the backend and the BFF, since both stay in the foreground).

### 1. Start the backend (LLM service, :8080)

```bash
cd apps/llm-demo/backend
export SPRING_AI_OPENAI_API_KEY=sk-...               # your real key
mvn spring-boot:run                                  # serves http://localhost:8080
```

### 2. Start the BFF (relay, :8081) — in a second terminal

```bash
cd apps/llm-demo/bff
export LLM_SERVICE_BASE_URL=http://localhost:8080    # optional — this is the default
mvn spring-boot:run                                  # serves http://localhost:8081
```

The BFF needs no OpenAI key — it only forwards to the backend. Timeouts are tunable via
`LLM_HTTP_CONNECT_TIMEOUT` / `LLM_HTTP_READ_TIMEOUT` / `LLM_HTTP_CONNECTION_REQUEST_TIMEOUT`
(see `apps/llm-demo/bff/README.md`).

### 3. Smoke-test

Health on both services:

```bash
curl localhost:8080/health                           # -> ok   (backend)
curl localhost:8081/health                           # -> ok   (bff)
```

**SSE (streaming) through the BFF** — tokens should arrive progressively:

```bash
curl -N -X POST localhost:8081/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"say hi in 3 words"}'
# streams:  event: token ... (repeated) ... event: done  data:[DONE]
```

**REST (blocking) through the BFF** — one JSON payload after generation finishes:

```bash
curl -X POST localhost:8081/api/chat/rest \
  -H 'Content-Type: application/json' \
  -d '{"message":"say hi in 3 words"}'
# -> {"content":"..."}   (arrives all at once, not streamed)
```

If the SSE call streams `event: token` lines and the REST call returns a single JSON object, the
relay works. You can hit `:8080` directly with the same paths to compare the BFF against the
backend — the responses should be identical.

### 4. Open the frontend

The frontend calls **relative** `/api/chat` and `/api/chat/rest`, which resolve against whatever
origin serves it (that's how it works behind CloudFront in prod). For a pure-local run, point it at
the BFF — do **one** of these:

- **Quick tweak (easiest):** in `apps/llm-demo/frontend/index.html`, temporarily change
  ```js
  const SSE_URL  = '/api/chat';        // -> 'http://localhost:8081/api/chat'
  const REST_URL = '/api/chat/rest';   // -> 'http://localhost:8081/api/chat/rest'
  ```
  then open the file in your browser. *(Don't commit this change.)* The BFF sends
  `Access-Control-Allow-Origin: *`, so a `file://` page can call it.
- **No edit:** serve the file from any static server and reverse-proxy `/api` to `localhost:8081`.

Use the **SSE Streaming / REST (Blocking)** toggle to feel the difference: SSE tokens appear one by
one; REST shows a spinner, then the whole answer at once.

---

## B. Deploy to AWS (GitHub Actions)

Everything is driven by two manual workflows — **no local AWS tooling needed**. The pipeline builds
the JAR + image, provisions all infra with Terraform (ECS Fargate + ALB + ECR + S3 + CloudFront +
Secrets Manager), uploads the frontend, and prints the public URL.

Auth to AWS uses **GitHub OIDC** — the workflow assumes an IAM role via a short-lived token, so you
never type AWS access keys into a workflow form (which would otherwise leak in public run logs).

### 1. One-time setup

1. **Push this repo to GitHub** (the workflows live in `.github/workflows/`).
2. Add the OpenAI key as a **repository secret**:
   `Settings → Secrets and variables → Actions → New repository secret`
   - Name: `SPRING_AI_OPENAI_API_KEY`
   - Value: `sk-...`
3. **Bootstrap the OIDC role** — run the script and answer the prompts (it asks for your AWS
   account number + access key/secret each time; nothing is written to disk):
   ```bash
   ./scripts/create-github-oidc-role.sh   # prints the role ARN at the end
   ```
   Re-runnable (idempotent): run it again any time to update the role's permissions.

### 2. Deploy

`Actions` tab → **llm-demo deploy** → **Run workflow**, then fill in:

| Input          | Example                                            | Notes                                  |
| -------------- | -------------------------------------------------- | -------------------------------------- |
| `aws_role_arn` | `arn:aws:iam::123456789012:role/demoland-github-actions-deploy` | the `role_arn` from step B.1.3 (not sensitive) |
| `aws_region`   | `us-east-1`                                        | default                                |
| `image_tag`    | `latest`                                           | default                                |

Run it. When the job finishes, the **job summary** shows:

```
## llm-demo deployed 🚀
URL: https://xxxxxxxxxxxxx.cloudfront.net
```

Open that URL and start chatting. Give it a few minutes on first deploy — the ECS task needs to pass
health checks and CloudFront needs to finish propagating.

> First run takes longest (CloudFront distribution creation ~5–10 min). Re-deploys with a new
> `image_tag` are much faster.

### 3. Tear it down

`Actions` tab → **llm-demo destroy** → **Run workflow** → same `aws_role_arn` + `aws_region` inputs.

This removes ECS, ALB, ECR, S3, CloudFront, Secrets Manager, and the VPC. The Terraform **state
bucket** (`demoland-tfstate-<account_id>`) and lock table are intentionally kept for reuse.

> CloudFront deletion keeps running on AWS's side for **~15–20 min** after the job reports success.

---

## Troubleshooting

| Symptom                                    | Likely cause / fix                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------------------- |
| Deploy fails at "Check OpenAI API key"     | Repo secret `SPRING_AI_OPENAI_API_KEY` isn't set (Step B.1.2).                     |
| Local frontend can't reach the API         | You skipped the `SSE_URL` / `REST_URL` change in A.4 — relative `/api/*` won't hit :8081. |
| BFF returns 500 / can't reach backend      | Backend not up on :8080, or `LLM_SERVICE_BASE_URL` points at the wrong host.       |
| BFF stream cuts off mid-answer             | Bump `LLM_HTTP_READ_TIMEOUT` (gap between tokens) or `BFF_ASYNC_REQUEST_TIMEOUT` (total stream lifetime). |
| Page loads but chat 502s right after deploy | ECS task not healthy yet — wait 1–2 min, then retry.                               |
| Stream cuts off around ~60s                | CloudFront origin read timeout caps at 60s without a quota increase (see infra comments). |
| Deploy fails on state bucket / lock        | Another deploy is mid-run, or the OIDC role lacks S3/DynamoDB perms.                |
| `configure-aws-credentials` fails to assume role | Wrong `aws_role_arn`, or the role's trust policy doesn't match this repo (`GH_OWNER`/`GH_REPO` in the script). |

## Cost note

While up: ~1 Fargate task + 1 ALB + CloudFront ≈ a few USD/day. Run **llm-demo destroy** when done.

## Security note

The workflows use **GitHub OIDC**: no long-lived AWS access keys exist anywhere — the runner assumes
the IAM role (created by `scripts/create-github-oidc-role.sh`) with a short-lived token, and the only
workflow inputs (`aws_role_arn`, `aws_region`, `image_tag`) are non-sensitive. The OpenAI key lives
only in a GitHub repo secret → AWS Secrets Manager, never in logs or frontend code. The role's IAM
policy is intentionally broad for the demo; scope it down in `scripts/create-github-oidc-role.sh` for
real use.
