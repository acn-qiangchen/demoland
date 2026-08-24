# ---------------------------------------------------------------------------
# GitHub Actions OIDC → AWS IAM role.
#
# Run this ONCE, by a human, with admin-ish local credentials (aws configure /
# aws sso). It creates:
#   - the GitHub OIDC identity provider (token.actions.githubusercontent.com)
#   - an IAM role scoped to THIS repo that the deploy/destroy workflows assume
#     via a short-lived OIDC token — so no static AWS keys ever exist.
#
# Output `role_arn` is the value you pass as the `aws_role_arn` workflow input.
# ---------------------------------------------------------------------------

# Fetch the issuer's TLS cert so the OIDC provider thumbprint is always current
# (avoids hardcoding a fingerprint that AWS/GitHub may rotate).
data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = { Name = "github-actions-oidc" }
}

# Reuse an existing provider when create_oidc_provider = false.
data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

# Trust policy: only tokens from this repo, with the sts.amazonaws.com audience,
# may assume the role. Two sub patterns are allowed: the plain form and the
# immutable-ID form (repo:owner@<ownerId>/repo@<repoId>:*) that some orgs/enterprises
# emit when they customize the OIDC subject claim. Tighten the `sub` to a
# branch/environment if you want to restrict which refs can deploy,
# e.g. "repo:owner/repo:ref:refs/heads/main".
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/${var.github_repo}:*",
        "repo:${var.github_owner}@*/${var.github_repo}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = { Name = var.role_name }
}

# Permissions the deploy/destroy workflows need. Broad service-level access to
# keep the demo working end-to-end; scope these down for anything beyond a demo.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid    = "InfraServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "apigateway:*",
      "s3:*",
      "cloudfront:*",
      "secretsmanager:*",
      "logs:*",
      "dynamodb:*",
      "application-autoscaling:*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # Terraform creates/deletes the ECS task execution + task roles and passes them
  # to ECS, so the deploy role needs role-management + PassRole.
  statement {
    sid    = "IamForEcsRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
