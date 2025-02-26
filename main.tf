locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region != "" ? var.region : data.aws_region.current.name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "pull_through_cache_repository_template" {
  for_each = var.registries

  source  = "terraform-aws-modules/ecr/aws//modules/repository-template"
  version = "2.3.1"

  # Template
  description   = "Pull through cache repository template for ${each.key} artifacts"
  prefix        = each.key
  resource_tags = var.tags

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 3 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 3
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  # Pull through cache rule
  create_pull_through_cache_rule = true
  upstream_registry_url          = each.value.registry
  credential_arn                 = module.secrets_manager_credentials[each.key].secret_arn

  tags = var.tags
}

module "secrets_manager_credentials" {
  for_each = var.registries
  source   = "terraform-aws-modules/secrets-manager/aws"
  version  = "1.3.1"

  # Secret names must contain 1-512 Unicode characters and be prefixed with ecr-pullthroughcache/
  name_prefix = "ecr-pullthroughcache/${each.key}"
  description = "${each.key} credentials"

  # For example only
  recovery_window_in_days = 0
  secret_string = jsonencode({
    username    = each.value.username
    accessToken = each.value.accessToken
  })

  # Policy
  create_policy       = true
  block_public_policy = true
  policy_statements = {
    read = {
      sid = "AllowAccountRead"
      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:root"]
      }]
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["*"]
    }
  }

  tags = var.tags
}
