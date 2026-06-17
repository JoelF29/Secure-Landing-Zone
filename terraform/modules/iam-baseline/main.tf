# Module IAM baseline — moindre privilège.
# Skeleton à compléter.

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_symbols                = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  allow_users_to_change_password = true
  max_password_age            = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
  
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "slz-account-analyzer-${var.environment}"
  type = "ACCOUNT"
}

#ressource qui dit à aws de faire confiance aux jetons de github pour l'authentification des workflows github actions
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b343a5d0e4b9e3b6fa"] # AWS ignore ce thumbprint pour GitHub depuis 2023 ; requis par le provider Terraform.
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]  # l'ARN du provider OIDC que tu as créé
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]  # l'audience que tu as définie pour le provider OIDC
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"] # l'identifiant du repo et de la branche que tu veux autoriser. Et fait de cette façon l module est réutilisable pour d'autres repos et branches.
    }
  }
}

resource "aws_iam_role" "github_actions_role" {
  name               = "github-actions-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
  description        = "Role for GitHub Actions to access AWS resources in ${var.environment} environment"
  permissions_boundary = aws_iam_policy.deploy_boundary.arn

}

data "aws_iam_policy_document" "deploy_permissions" {

  statement {
    sid       = "ComputeAndNetwork"
    effect    = "Allow"
    actions   = ["ec2:DescribeVpcs", "ec2:CreateVpc", "ec2:DeleteVpc",
                 "ec2:CreateSubnet", "ec2:DeleteSubnet",
                 "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
                 "ec2:AuthorizeSecurityGroupIngress"]
    resources = ["*"]
  }

  statement {
    sid       = "Storage"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]  # actions S3 dont Terraform a besoin
    resources = ["*"]
  }

  statement {
    sid       = "IamBaseline"
    effect    = "Allow"
    actions   = ["iam:GetRole", "iam:ListRoles", "iam:CreateRole", "iam:AttachRolePolicy"]  # actions IAM limitées (Get*, List*, CreateRole, AttachRolePolicy...)
    resources = ["*"]
  }

  statement {
    sid       = "Logging"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]  # actions CloudWatch Logs
    resources = ["*"]
  }

  statement {
    sid       = "KeyManagement"
    effect    = "Allow"
    actions   = ["kms:CreateKey", "kms:DescribeKey", "kms:Encrypt", "kms:Decrypt"]  # actions KMS
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_permissions"{
  name        = "slz-deploy-permissions-${var.environment}"
  description = "Policy for GitHub Actions to deploy resources in ${var.environment} environment"
  policy      = data.aws_iam_policy_document.deploy_permissions.json
}

resource "aws_iam_role_policy_attachment" "deploy_permissions" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.deploy_permissions.arn
}

resource "aws_iam_policy" "deploy_boundary" {
  name        = "slz-deploy-boundary-${var.environment}"
  description = "Policy for GitHub Actions to deploy resources in ${var.environment} environment"
  policy      = data.aws_iam_policy_document.deploy_permissions.json
}
# TODO: rôles scopés par fonction (pas de politique "*:*").
# TODO: fédération OIDC pour le CI/CD (pas de clés d'accès statiques long-terme).
# TODO: politique de mot de passe / MFA obligatoire.
# TODO: séparation des privilèges de déchiffrement KMS.
