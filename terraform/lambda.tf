data "archive_file" "checkout_api" {
  type        = "zip"
  source_dir  = "${path.module}/../src/api"
  output_path = "${path.module}/../dist/checkout_api.zip"
}

data "aws_ssm_parameter" "powertools_layer" {
  name = "/aws/service/powertools/python/x86_64/python3.13/latest"
}

resource "aws_ssm_parameter" "log_level" {
  name  = "/${local.project_name}/${terraform.workspace}/config/log-level"
  type  = "String"
  value = "INFO"

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-log-level"
  }
}

resource "aws_lambda_function" "checkout_api" {
  filename         = data.archive_file.checkout_api.output_path
  function_name    = "${local.function_name}-${terraform.workspace}"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.checkout_api.output_base64sha256
  timeout          = 10
  memory_size      = 1536 # Will run a profilier to test when I can reduce this to 1024 or 512
  layers           = [data.aws_ssm_parameter.powertools_layer.value]

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME  = local.function_name
      LOG_LEVEL_PARAMETER_NAME = aws_ssm_parameter.log_level.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name = "${local.function_name}-${terraform.workspace}"
  }
}
