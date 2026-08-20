resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-github"
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${local.short_name}-${terraform.workspace}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:StephanBailey@30832638/checkout-cloud-platform-assessment@1339505678:environment:${terraform.workspace}"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-github-actions"
  }
}

data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "TerraformStateBackend"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::checkout-cloud-platform-assessment-tfstate",
      "arn:aws:s3:::checkout-cloud-platform-assessment-tfstate/*",
    ]
  }

  statement {
    sid    = "InfrastructureServices"
    effect = "Allow"

    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "lambda:*",
      "logs:*",
      "sns:*",
      "cloudwatch:*",
      "ssm:*",
      "acm:*",
      "secretsmanager:*",
      "sts:GetCallerIdentity",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ProjectS3Buckets"
    effect = "Allow"

    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.project_name}-*", "arn:aws:s3:::${local.project_name}-*/*"]
  }

  statement {
    sid    = "IAMRoleManagementScoped"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]

    resources = ["arn:aws:iam::*:role/${local.short_name}-*"]
  }

  statement {
    sid    = "IAMPassRoleLambdaExecutionOnly"
    effect = "Allow"

    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/${local.short_name}-*-lambda-execution"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "IAMOidcProviderScoped"
    effect = "Allow"

    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]

    resources = ["arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com"]
  }
}

resource "aws_iam_policy" "github_actions_deploy" {
  name   = "${local.short_name}-${terraform.workspace}-deploy"
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}
