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

# TODO: scope this to exactly the actions this stack needs instead of
# AdministratorAccess - kept broad here as a skeleton of the OIDC trust
# pattern, not a hardened deploy policy.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
