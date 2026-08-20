# bootstrap — GitHub Actions OIDC → AWS

Setup that lets the `llm-demo-deploy` / `llm-demo-destroy` workflows authenticate to AWS
**without any long-lived access keys**. It creates a GitHub OIDC identity provider and an IAM
role, scoped to this repo, that the workflows assume via a short-lived token.

Two equivalent ways to do it — use whichever you prefer.

## Option A — shell script (recommended if you swap AWS accounts/keys often)

Prompts for the AWS account number + access key/secret each run; those creds are used only for
this one setup call and are never written to disk. Re-runnable (idempotent).

```bash
./infra/bootstrap/create-github-oidc-role.sh
# ...answer the prompts, then copy the printed role ARN.
```

## Option B — Terraform

Run once, with admin-capable local credentials (`aws configure` or `aws sso login`):

```bash
cd infra/bootstrap
terraform init
terraform apply -var 'github_owner=acn-qiangchen' -var 'github_repo=demoland'
terraform output role_arn
```

Then, when you run the **deploy** or **destroy** workflow in GitHub Actions, paste that role ARN into
the **`aws_role_arn`** input. There are no access-key/secret inputs anymore — nothing sensitive is
ever typed into a workflow form or written to a log.

## Notes
- **Provider already exists?** Only one `token.actions.githubusercontent.com` OIDC provider is
  allowed per AWS account. If `apply` fails with `EntityAlreadyExists`, either:
  - re-run with `-var 'create_oidc_provider=false'` to reuse the existing provider, or
  - import it: `terraform import aws_iam_openid_connect_provider.github[0] arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`
- **State:** this module uses local Terraform state by design (it must exist before any remote/OIDC
  flow works). Keep its `terraform.tfstate` safe, or import the resources later if you lose it.
- **Least privilege:** the role's policy uses broad service-level actions to keep the demo working
  end-to-end. Scope `main.tf`'s policy down for anything beyond a throwaway demo.
- **Restrict which refs can deploy:** by default any ref in the repo can assume the role
  (`repo:owner/repo:*`). Tighten the trust `sub` condition in `main.tf` to e.g.
  `repo:owner/repo:ref:refs/heads/main` if desired.
