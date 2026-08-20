resource "aws_lb" "checkout_api" {
  name               = "${local.short_name}-${terraform.workspace}"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = terraform.workspace == "prod"

  access_logs {
    bucket  = aws_s3_bucket.alb_access_logs.id
    prefix  = "${local.short_name}-${terraform.workspace}"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_access_logs]

  tags = {
    Name = "${local.short_name}-${terraform.workspace}"
  }
}

# CA bundle for validating client certificates, sourced from certificates.tf.
resource "aws_lb_trust_store" "checkout_api" {
  name = "${local.short_name}-${terraform.workspace}-ts"

  ca_certificates_bundle_s3_bucket         = aws_s3_bucket.trust_store.id
  ca_certificates_bundle_s3_key            = aws_s3_object.ca_bundle.key
  ca_certificates_bundle_s3_object_version = aws_s3_object.ca_bundle.version_id

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-trust-store"
  }
}

resource "aws_lb_target_group" "checkout_api" {
  name        = "${local.short_name}-${terraform.workspace}-tg"
  target_type = "lambda"

  # Health check invokes the Lambda function directly with a synthetic
  # request (no protocol/port for lambda-type targets).
  health_check {
    enabled = true
    path    = "/"
    matcher = "200"
  }

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-tg"
  }
}

resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.checkout_api.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.checkout_api.arn
}

resource "aws_lb_target_group_attachment" "checkout_api" {
  target_group_arn = aws_lb_target_group.checkout_api.arn
  target_id        = aws_lambda_function.checkout_api.arn

  depends_on = [aws_lambda_permission.alb_invoke]
}

resource "aws_lb_listener" "checkout_api" {
  load_balancer_arn = aws_lb.checkout_api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb_server.arn

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.checkout_api.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.checkout_api.arn
  }
}
