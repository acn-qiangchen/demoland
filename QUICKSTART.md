# Quick Start — llm-demo

A copy-paste guide to **run the streaming chat demo locally** and **deploy/tear it down on AWS**.
For the architecture and why things are wired this way, see
[`apps/llm-demo/README.md`](apps/llm-demo/README.md) and [`llm-demo-architecture.md`](llm-demo-architecture.md).

You need an **OpenAI API key** (starts with `sk-...`) for both paths.

---

## A. Run locally

**Prereqs:** JDK 17, Maven 3.9+. (Check: `java -version` → 17, `mvn -v`.)

### 1. Start the backend

```bash
cd apps/llm-demo/backend
export SPRING_AI_OPENAI_API_KEY=sk-...               # your real key
mvn spring-boot:run                                  # serves http://localhost:8080
```

### 2. Smoke-test it

```bash
curl localhost:8080/health                           # -> ok

curl -N -X POST localhost:8080/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"say hi in 3 words"}'
# streams:  event: token ... (repeated) ... event: done  data:[DONE]
```

If you see `event: token` lines streaming in, the backend works.

### 3. Open the frontend

The frontend calls a **relative** `/api/chat`, which only resolves when served from the same origin
as the API (that's how it works behind CloudFront in prod). For a pure-local run, do **one** of these:

- **Quick tweak (easiest):** in `apps/llm-demo/frontend/index.html`, temporarily change
  `const API_URL = '/api/chat';` → `const API_URL = 'http://localhost:8080/api/chat';`
  then open the file in your browser. *(Don't commit this change.)*
- **No edit:** serve the file from any static server and reverse-proxy `/api` to `localhost:8080`.

Type a prompt and watch tokens stream in.

---

## B. Deploy to AWS (GitHub Actions)

Everything is driven by two manual workflows — **no local AWS tooling needed**. The pipeline builds
the JAR + image, provisions all infra with Terraform (ECS Fargate + ALB + ECR + S3 + CloudFront +
Secrets Manager), uploads the frontend, and prints the public URL.

### 1. One-time setup

1. **Push this repo to GitHub** (the workflows live in `.github/workflows/`).
2. Add the OpenAI key as a **repository secret**:
   `Settings → Secrets and variables → Actions → New repository secret`
   - Name: `SPRING_AI_OPENAI_API_KEY`
   - Value: `sk-...`
3. Have an **AWS access key / secret** for an account with permission to create VPC, ECS, ALB, ECR,
   S3, CloudFront, IAM, and Secrets Manager resources.

### 2. Deploy

`Actions` tab → **llm-demo deploy** → **Run workflow**, then fill in:

| Input                   | Example        | Notes                                  |
| ----------------------- | -------------- | -------------------------------------- |
| `aws_account_id`        | `123456789012` | your 12-digit account ID               |
| `aws_access_key_id`     | `AKIA...`      | masked in logs                         |
| `aws_secret_access_key` | `...`          | masked in logs                         |
| `aws_region`            | `us-east-1`    | default                                |
| `image_tag`             | `latest`       | default                                |

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

`Actions` tab → **llm-demo destroy** → **Run workflow** → same AWS credential inputs.

This removes ECS, ALB, ECR, S3, CloudFront, Secrets Manager, and the VPC. The Terraform **state
bucket** (`demoland-tfstate-<account_id>`) and lock table are intentionally kept for reuse.

> CloudFront deletion keeps running on AWS's side for **~15–20 min** after the job reports success.

---

## Troubleshooting

| Symptom                                    | Likely cause / fix                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------------------- |
| Deploy fails at "Check OpenAI API key"     | Repo secret `SPRING_AI_OPENAI_API_KEY` isn't set (Step B.1.2).                     |
| Local frontend can't reach the API         | You skipped the `API_URL` change in A.3 — relative `/api/chat` won't hit :8080.    |
| Page loads but chat 502s right after deploy | ECS task not healthy yet — wait 1–2 min, then retry.                               |
| Stream cuts off around ~60s                | CloudFront origin read timeout caps at 60s without a quota increase (see infra comments). |
| Deploy fails on state bucket / lock        | Another deploy is mid-run, or creds lack S3/DynamoDB perms.                         |

## Cost note

While up: ~1 Fargate task + 1 ALB + CloudFront ≈ a few USD/day. Run **llm-demo destroy** when done.

## Security note

AWS credentials are passed as `workflow_dispatch` inputs and are masked in logs, but still appear in
run metadata. For anything beyond a throwaway demo, prefer GitHub OIDC or repo secrets.
