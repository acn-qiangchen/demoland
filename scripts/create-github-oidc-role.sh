#!/usr/bin/env bash
#
# create-github-oidc-role.sh
#
# Creates (idempotently) the GitHub Actions OIDC identity provider and the IAM role
# that the llm-demo deploy/destroy workflows assume via a short-lived OIDC token —
# so no long-lived AWS keys ever live in GitHub.
#
# It PROMPTS for the AWS account number + access key/secret every run (handy when you
# rotate accounts/keys often). Those creds are used only for this one setup call and
# are never written to disk.
#
# Requirements: awscli v2, and permission to manage IAM (create OIDC provider + role).
#
# Usage:
#   ./infra/bootstrap/create-github-oidc-role.sh
# Then paste the printed role ARN into the `aws_role_arn` input of the workflows.

set -euo pipefail

# ---- Defaults (override at the prompts) ------------------------------------
DEFAULT_REGION="us-east-1"
DEFAULT_OWNER="acn-qiangchen"
DEFAULT_REPO="demoland"
DEFAULT_ROLE="demoland-github-actions-deploy"

OIDC_HOST="token.actions.githubusercontent.com"
# GitHub's published OIDC thumbprints. AWS validates this IdP against its own trust
# store, so these are not security-critical, but the CLI still requires the flag.
THUMBPRINTS="6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fca"

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found on PATH." >&2; exit 1; }

# ---- Collect input ---------------------------------------------------------
read -rp "AWS account number: " ACCOUNT_ID
read -rp "AWS access key ID: " AWS_ACCESS_KEY_ID
read -rsp "AWS secret access key: " AWS_SECRET_ACCESS_KEY; echo
read -rp "AWS session token (blank if none): " AWS_SESSION_TOKEN
read -rp "AWS region [${DEFAULT_REGION}]: " REGION;      REGION="${REGION:-$DEFAULT_REGION}"
read -rp "GitHub owner [${DEFAULT_OWNER}]: " GH_OWNER;   GH_OWNER="${GH_OWNER:-$DEFAULT_OWNER}"
read -rp "GitHub repo [${DEFAULT_REPO}]: " GH_REPO;      GH_REPO="${GH_REPO:-$DEFAULT_REPO}"
read -rp "Role name [${DEFAULT_ROLE}]: " ROLE_NAME;      ROLE_NAME="${ROLE_NAME:-$DEFAULT_ROLE}"

[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo "ERROR: account number must be 12 digits." >&2; exit 1; }
[[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]] || { echo "ERROR: access key and secret are required." >&2; exit 1; }

# Export for this process only (the script runs in its own subprocess).
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="$REGION" AWS_REGION="$REGION"
[[ -n "$AWS_SESSION_TOKEN" ]] && export AWS_SESSION_TOKEN

# ---- Verify identity -------------------------------------------------------
echo "==> Verifying credentials..."
CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$CALLER_ACCOUNT" != "$ACCOUNT_ID" ]]; then
  echo "ERROR: these keys belong to account ${CALLER_ACCOUNT}, not ${ACCOUNT_ID}." >&2
  exit 1
fi
echo "    OK — account ${ACCOUNT_ID}, region ${REGION}."

# Temp dir for policy documents; cleaned up on exit.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"

# ---- 1. OIDC identity provider (create if missing) -------------------------
echo "==> Ensuring OIDC provider ${OIDC_HOST}..."
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "    Already exists — reusing."
else
  # shellcheck disable=SC2086
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_HOST}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list $THUMBPRINTS >/dev/null
  echo "    Created."
fi

# ---- 2. Trust policy (who may assume the role) -----------------------------
cat >"${WORKDIR}/trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${OIDC_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "${OIDC_HOST}:aud": "sts.amazonaws.com" },
        "StringLike":   {
          "${OIDC_HOST}:sub": [
            "repo:${GH_OWNER}/${GH_REPO}:*",
            "repo:${GH_OWNER}@*/${GH_REPO}@*:*"
          ]
        }
      }
    }
  ]
}
JSON

# ---- 3. Permissions policy (what the workflow may do) ----------------------
# Broad service-level access to keep the demo working end-to-end. Scope down for real use.
cat >"${WORKDIR}/perms.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InfraServices",
      "Effect": "Allow",
      "Action": [
        "ec2:*", "ecs:*", "ecr:*", "elasticloadbalancing:*", "s3:*",
        "cloudfront:*", "secretsmanager:*", "logs:*", "dynamodb:*",
        "application-autoscaling:*", "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForEcsRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
        "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole", "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*"
    }
  ]
}
JSON

# ---- 4. Role (create or update trust) --------------------------------------
echo "==> Ensuring IAM role ${ROLE_NAME}..."
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" \
    --policy-document "file://${WORKDIR}/trust.json"
  echo "    Existed — trust policy updated."
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${WORKDIR}/trust.json" \
    --max-session-duration 3600 \
    --description "GitHub Actions OIDC deploy role for ${GH_OWNER}/${GH_REPO}" >/dev/null
  echo "    Created."
fi

# ---- 5. Attach inline permissions ------------------------------------------
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "${ROLE_NAME}-policy" \
  --policy-document "file://${WORKDIR}/perms.json"
echo "    Permissions policy applied."

# ---- Done ------------------------------------------------------------------
ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"
echo
echo "============================================================"
echo " Done. Use this as the workflow 'aws_role_arn' input:"
echo
echo "   ${ROLE_ARN}"
echo
echo " Trust scope: repo:${GH_OWNER}/${GH_REPO} (plain or owner@id/repo@id form), any ref"
echo "============================================================"
