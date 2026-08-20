resource "aws_iam_role" "lambda_execution" {
  name = "${local.short_name}-${terraform.workspace}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-lambda-execution"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    sid    = "WriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "logs"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}

data "aws_iam_policy_document" "lambda_runtime_config" {
  statement {
    sid    = "ReadRuntimeConfig"
    effect = "Allow"

    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.log_level.arn]
  }
}

resource "aws_iam_role_policy" "lambda_runtime_config" {
  name   = "runtime-config"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_runtime_config.json
}
