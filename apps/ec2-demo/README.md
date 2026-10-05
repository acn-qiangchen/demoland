# ec2-demo

A minimal **pure-infrastructure** demo: Terraform provisions one standalone EC2 instance
(Amazon Linux 2023, `t3.micro` by default) in its own VPC, reachable two ways:

1. **SSH** — with the private key matching the public key hardcoded in
   `infra/ec2-demo/terraform/keypair.tf`.
2. **SSM Session Manager** — a browser/CLI shell with **no inbound port and no key**. AL2023
   ships the SSM agent preinstalled; the instance has an IAM instance profile granting
   `AmazonSSMManagedInstanceCore` and egress to the public SSM endpoints, so this works out of
   the box.

## Infra inventory (`infra/ec2-demo/terraform/`)

- **VPC** `10.0.0.0/16` + internet gateway, one public subnet (auto-assign public IP), public
  route table + association.
- **Security group** `ec2-demo-sg`: ingress TCP 22 from `allowed_ssh_cidr` (default
  `0.0.0.0/0`), egress all. Egress-all is required for the SSM agent to reach its endpoints —
  no VPC interface endpoints needed.
- **Key pair** `ec2-demo-key` with your hardcoded public key.
- **IAM**: role `ec2-demo-ssm-role` (EC2 trust) + `AmazonSSMManagedInstanceCore` attachment,
  wrapped in instance profile `ec2-demo-ssm-profile`.
- **EC2 instance** `ec2-demo`: latest AL2023 AMI (resolved via a public SSM parameter),
  in the public subnet with a public IP.

## Access

After deploy, the workflow job summary prints both commands (values come from Terraform
outputs `ssh_command` / `ssm_command`):

```bash
# SSH (needs the private key matching the hardcoded public key)
ssh -i /path/to/your/private_key ec2-user@<public_ip>

# SSM Session Manager (no key, no inbound port; needs the AWS CLI + session-manager-plugin)
aws ssm start-session --target <instance_id>
```

Narrow SSH exposure by setting `allowed_ssh_cidr` to your own IP (e.g. `203.0.113.4/32`).

## Deviations from the per-app contract

This demo keeps every `app.json` field for schema consistency, but some are N/A:

- **No container / ECR build.** There is no `Dockerfile`, `.dockerignore`, or `src/` — this is
  infrastructure only, so the deploy workflow has no JDK/Maven or docker build/push steps.
- **`port` / `healthEndpoint` are `null`** — there is no server process to expose or health-check
  (same deviation `osaga-demo` documents).
- **`resources` is N/A** — CPU/memory requests/limits describe a container; this demo runs a VM
  sized by `instance_type`, not a scheduled container. The field is kept (zeroed) for schema
  consistency only.

## One-time OIDC role re-sync (required before first deploy)

Per the `CLAUDE.md` "new infra services need matching OIDC permissions" rule, this demo adds AWS
actions the shared deploy role didn't have (`ssm:*` for the AMI lookup, plus the instance-profile
`iam:*` actions). A human must re-run the role sync **once** before the first `ec2-demo` deploy:

```bash
./scripts/create-github-oidc-role.sh
```

It idempotently re-applies the inline policy. Without this, `terraform apply` fails with
`AccessDenied` on the SSM parameter read and the instance-profile resources.
