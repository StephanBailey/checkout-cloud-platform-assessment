resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}-${terraform.workspace}"
  retention_in_days = 30

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-lambda"
  }
}

resource "aws_s3_bucket" "alb_access_logs" {
  bucket        = "${local.project_name}-${terraform.workspace}-alb-access-logs" # TODO: confirm globally-unique real bucket name
  force_destroy = true

  tags = {
    Name = "${local.project_name}-${terraform.workspace}-alb-access-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "alb_access_logs" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_access_logs.arn, "${aws_s3_bucket.alb_access_logs.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowElasticLoadBalancingLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_access_logs.arn}/${local.short_name}-${terraform.workspace}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = data.aws_iam_policy_document.alb_access_logs.json
}

resource "aws_sns_topic" "alarms" {
  name = "${local.short_name}-${terraform.workspace}-alarms"

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-alarms"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.short_name}-${terraform.workspace}-lambda-errors"
  alarm_description   = "Lambda function invocation errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.checkout_api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-lambda-errors"
  }
}
