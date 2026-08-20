# 🚀 Demoland

**A platform for deploying and showcasing application demos.**

Demoland is a monorepo that hosts multiple independent demo applications and the shared infrastructure to run them. Each demo lives in `apps/` with its own container and deployment config; shared platform infrastructure (networking, cluster, ingress, monitoring) lives in `infra/platform/`.

---

## Repository Structure

```
demoland/
├── apps/                    # Demo applications (one directory per demo)
│   └── _template/           # Copy this to scaffold a new demo
├── infra/
│   ├── platform/            # Shared infrastructure (VPC, cluster, ingress, DNS)
│   │   └── terraform/
│   └── app-template/        # Per-app infrastructure template
│       └── terraform/
├── platform/
│   ├── gateway/             # Ingress / routing configuration
│   └── monitoring/          # Observability stack (Prometheus, Grafana, Loki)
├── scripts/                 # CLI helpers
│   ├── new-demo.sh          # Scaffold a new demo app
│   ├── deploy.sh            # Deploy a specific app
│   └── destroy.sh           # Tear down a specific app
├── docs/                    # Architecture & contributor guides
└── .github/
    ├── workflows/           # CI/CD pipelines
    └── ISSUE_TEMPLATE/      # New demo requests, bug reports
```

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://developer.hashicorp.com/terraform) | ≥ 1.6 | Infrastructure provisioning |
| [Docker](https://docs.docker.com/get-docker/) | ≥ 24 | Container builds |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.28 | Cluster management |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.12 | Kubernetes package management |
| [GitHub CLI](https://cli.github.com/) | ≥ 2.x | Repository operations |

### 1 — Bootstrap the platform infrastructure

```bash
cd infra/platform/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your cloud credentials and settings
terraform init
terraform plan
terraform apply
```

### 2 — Add a new demo

```bash
./scripts/new-demo.sh my-app-name
# Follow the prompts, then edit apps/my-app-name/
```

### 3 — Deploy a demo

```bash
./scripts/deploy.sh my-app-name [staging|prod]
```

The demo will be available at `https://<app-name>.demoland.<your-domain>`.

---

## Adding a Demo

See **[docs/adding-a-demo.md](docs/adding-a-demo.md)** for a full walkthrough.

The short version:

1. Run `./scripts/new-demo.sh <name>` — copies `apps/_template/` and wires up CI.
2. Build your app in `apps/<name>/src/`.
3. Update `apps/<name>/app.json` with metadata (name, description, port, env vars).
4. Push a PR — the CI pipeline builds, lints, and validates the container.
5. Merge → auto-deploy to staging; promote to prod via the GitHub Actions workflow dispatch.

---

## Environments

| Environment | Trigger | URL pattern |
|-------------|---------|-------------|
| **staging** | Merge to `main` | `https://<app>.staging.demoland.<domain>` |
| **prod** | Manual workflow dispatch | `https://<app>.demoland.<domain>` |

---

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Getting Started](docs/getting-started.md)
- [Adding a Demo App](docs/adding-a-demo.md)
- [Infrastructure Guide](docs/infrastructure.md)
- [Contributing](CONTRIBUTING.md)

---

## License

MIT — see [LICENSE](LICENSE).
