# run once per environment with admin creds (from your laptop)
# creates the state bucket, github oidc provider and two roles: plan (read only) and apply
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.81"
    }
  }
}

variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "org_prefix" {
  description = "state bucket prefix, e.g. barba"
  type        = string
}

variable "github_repo" {
  description = "owner/repo"
  type        = string
}

variable "github_sub_prefix" {
  description = "oidc sub prefix, empty means repo:<github_repo>"
  type        = string
  default     = ""
}

locals {
  sub_prefix = var.github_sub_prefix != "" ? var.github_sub_prefix : "repo:${var.github_repo}"
}

variable "create_oidc_provider" {
  description = "false if the account already has the github oidc provider"
  type        = bool
  default     = true
}

variable "apply_policy_arns" {
  description = "admin is just for the demo, tighten it"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.org_prefix}-tfstate-${var.environment}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.sub_prefix}:pull_request",
        "${local.sub_prefix}:ref:refs/heads/dev",
        "${local.sub_prefix}:ref:refs/heads/staging",
        "${local.sub_prefix}:ref:refs/heads/main",
      ]
    }
  }
}

# apply role only works from the matching github environment (that is where the prod approval lives)
data "aws_iam_policy_document" "trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.sub_prefix}:environment:${var.environment}"]
    }
  }
}

data "aws_iam_policy_document" "state_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

data "aws_iam_policy_document" "state_rw" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role" "plan" {
  name               = "gha-tf-plan-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.trust_plan.json
}

resource "aws_iam_role_policy_attachment" "plan_ro" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_read.json
}

resource "aws_iam_role" "apply" {
  name               = "gha-tf-apply-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.trust_apply.json
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each   = toset(var.apply_policy_arns)
  role       = aws_iam_role.apply.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "state-rw"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state_rw.json
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}
