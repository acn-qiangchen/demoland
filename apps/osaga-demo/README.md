# osaga-demo — Orchestration Saga (S3 → EventBridge → Step Functions → ECS Fargate + Spring Batch)

An **event-driven batch pipeline**. Drop a CSV in the input bucket and an orchestrated
saga runs a Spring Batch job on Fargate that transforms the file and writes the result to
an output bucket. Unlike `llm-demo` (an always-on web service), this app is a **batch job**:
it runs once and exits, and its exit code drives the saga's success / failure branches.

```
   upload CSV
       │
       ▼
┌───────────────┐   Object Created   ┌──────────────┐   StartExecution   ┌──────────────────┐
│  S3 input     │ ─────────────────▶ │ EventBridge  │ ─────────────────▶ │  Step Functions  │
│  bucket       │   (event)          │ rule         │                    │  state machine   │
└───────────────┘                    └──────────────┘                    └────────┬─────────┘
                                                                                   │ ecs:runTask.sync
                                                                                   │ (waits for exit)
                                                                                   ▼
                                                                          ┌──────────────────┐
                                                                          │  ECS Fargate     │
                                                                          │  Spring Batch    │
                                                                          │  CSV transform   │
                                                                          └────────┬─────────┘
                                                                                   │ PutObject
                                                                                   ▼
                                                                          ┌──────────────────┐
                                                                          │  S3 output       │
                                                                          │  processed/…     │
                                                                          └──────────────────┘
```

The state machine's **Retry** (transient faults) and **Catch → Fail** (permanent failure)
are the "saga" orchestration: a non-zero container exit surfaces as `States.TaskFailed` and
routes to the terminal `Failed` state instead of `Succeeded`.

## What the batch job does

Reads the input CSV (`id,name,value`), **uppercases the `name` column**, appends a
**`processed_at`** timestamp column plus two columns threaded through from EventBridge —
**`batch_timestamp`** (the S3 event's `$.time`) and **`app_name`** (the literal
`osaga-demo`) — and writes the result CSV to
`s3://<output-bucket>/processed/<input-filename>`.

Output header: `id,name,value,processed_at,batch_timestamp,app_name`.

Example — `sample-data/input.csv`:

```
id,name,value        id,name,value,processed_at,batch_timestamp,app_name
1,alice,100    ─▶     1,ALICE,100,2026-08-29T00:00:00Z,2026-08-29T00:00:00Z,osaga-demo
2,bob,205             2,BOB,205,2026-08-29T00:00:00Z,2026-08-29T00:00:00Z,osaga-demo
```

The `batch_timestamp` and `app_name` values are **passed in from EventBridge** (via the
input transformer) into the Step Functions state machine and on to the ECS task as
**command-line arguments** (`--batchTimestamp=… --appName=…`) — the app only reads and
writes them, it does not generate them. See [Command-line arguments](#command-line-arguments).

## `app.json` note (batch vs. web template)

This demo deviates from the web-oriented `apps/_template/`: it has **no long-running port
or health endpoint**, so `port` and `healthEndpoint` in `app.json` are `null`. The fields
are kept for schema consistency. Batch demos are a distinct shape from the web template.

## Environment variables

Supplied at runtime as **RunTask container overrides** by Step Functions (from the S3 event):

| Var             | Meaning                                                            |
| --------------- | ----------------------------------------------------------------- |
| `INPUT_BUCKET`  | Bucket holding the input CSV                                       |
| `INPUT_KEY`     | Object key of the input CSV                                        |
| `OUTPUT_BUCKET` | Bucket to write the transformed CSV to                            |
| `OUTPUT_KEY`    | Output key (optional; defaults to `processed/<input-filename>`)    |

The app uses AWS SDK v2, which picks up credentials from the ECS **task role** automatically
— no keys anywhere.

## Command-line arguments

Two parameters reach the app as **plain named command-line arguments** (not env vars), parsed
manually from Spring Boot's `ApplicationArguments` in `S3JobRunner`:

| Arg                       | Meaning                                                                                              |
| ------------------------- | --------------------------------------------------------------------------------------------------- |
| `--batchTimestamp=<val>`  | Written as the `batch_timestamp` column; sourced from the EventBridge event `$.time`                 |
| `--appName=<val>`         | Written as the `app_name` column; the literal `osaga-demo` from the EventBridge input template       |

The flow is: EventBridge event → input transformer (`$.time` / literal) → Step Functions input
JSON → ECS **`Command` override** (`--batchTimestamp=… --appName=…`, appended to the Dockerfile
`ENTRYPOINT`) → `ApplicationArguments` → `JobParameters` → the writer columns. Both are
**optional** — when omitted (e.g. local runs), `batch_timestamp` defaults to `Instant.now()`
and `app_name` to `osaga-demo`.

## Run locally

Requires JDK 17 and Maven.

```bash
cd apps/osaga-demo
mvn clean package            # compiles, runs the unit test, builds the jar
```

**Local-file mode** (no AWS): if `INPUT_BUCKET` is unset, `INPUT_KEY` is treated as a local
input path and `OUTPUT_KEY` as a local output path — S3 is skipped entirely.

```bash
INPUT_KEY=sample-data/input.csv OUTPUT_KEY=/tmp/out.csv \
  java -jar target/osaga-demo-0.1.0.jar \
  --batchTimestamp=2026-08-30T12:00:00Z --appName=osaga-demo
cat /tmp/out.csv
```

The `--batchTimestamp` / `--appName` args are optional locally — if omitted they default to
the current time (`Instant.now()`) and `osaga-demo` respectively.

Build the container (multi-stage, runs as non-root):

```bash
docker build -t osaga-demo .
```

## Deploy to AWS

> **One-time role update (required).** The shared deploy role gained
> `states:*` / `events:*` permissions for this demo. A human must re-run
> [`scripts/create-github-oidc-role.sh`](../../scripts/create-github-oidc-role.sh) once
> (it idempotently overwrites the role's inline policy) before the first osaga-demo deploy,
> otherwise Terraform can't create the Step Functions / EventBridge resources.

1. Run the **osaga-demo deploy** GitHub Actions workflow (`workflow_dispatch`), passing the
   IAM role ARN printed by `scripts/create-github-oidc-role.sh`. The job summary prints the
   input/output bucket names and the state machine ARN.
2. Trigger the pipeline by uploading the sample file:

   ```bash
   aws s3 cp apps/osaga-demo/sample-data/input.csv s3://<input-bucket>/
   ```

3. Watch it run:

   ```bash
   aws stepfunctions list-executions --state-machine-arn <state-machine-arn>
   aws logs tail /ecs/osaga-demo --follow
   aws s3 ls s3://<output-bucket>/processed/
   ```

4. Tear down with the **osaga-demo destroy** workflow.

## Infrastructure

Self-contained Terraform lives in [`infra/osaga-demo/terraform/`](../../infra/osaga-demo/terraform/):
two S3 buckets (input with EventBridge notifications enabled + output), an ECR repo, a
Fargate cluster + task definition (no service — tasks are launched on demand), CloudWatch
logs, the EventBridge rule, the Step Functions state machine, and scoped IAM roles.
