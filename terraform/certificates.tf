data "aws_caller_identity" "current" {}

# --- Root CA ---

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 10

  subject {
    common_name  = "${local.project_name} Internal Root CA"
    organization = "Checkout Platform"
  }

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "aws_secretsmanager_secret" "ca_private_key" {
  name        = "${local.project_name}/${terraform.workspace}/mtls/ca-private-key"
  description = "Root CA private key for checkout API mTLS certificates."
}

resource "aws_secretsmanager_secret_version" "ca_private_key" {
  secret_id     = aws_secretsmanager_secret.ca_private_key.id
  secret_string = tls_private_key.ca.private_key_pem
}

# --- Server certificate (ALB listener) ---

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = local.alb_domain_name
    organization = "Checkout Platform"
  }

  dns_names = [local.alb_domain_name]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 24 * 365

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb_server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.project_name}-${terraform.workspace}-alb-server"
  }
}

# --- Client certificate (test/integration) ---

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${local.project_name}-test-client"
    organization = "Checkout Platform"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 24 * 365

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

resource "aws_secretsmanager_secret" "test_client_certificate" {
  name        = "${local.project_name}/${terraform.workspace}/mtls/test-client-certificate"
  description = "Test client certificate and private key for mTLS integration testing."
}

resource "aws_secretsmanager_secret_version" "test_client_certificate" {
  secret_id = aws_secretsmanager_secret.test_client_certificate.id
  secret_string = jsonencode({
    certificate_pem = tls_locally_signed_cert.client.cert_pem
    private_key_pem = tls_private_key.client.private_key_pem
  })
}

# --- Trust store bucket ---

resource "aws_s3_bucket" "trust_store" {
  bucket        = "${local.project_name}-${terraform.workspace}-trust-store" # TODO: confirm globally-unique real bucket name
  force_destroy = true

  tags = {
    Name = "${local.project_name}-${terraform.workspace}-trust-store"
  }
}

resource "aws_s3_bucket_versioning" "trust_store" {
  bucket = aws_s3_bucket.trust_store.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "trust_store" {
  bucket = aws_s3_bucket.trust_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trust_store" {
  bucket = aws_s3_bucket.trust_store.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "trust_store" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trust_store.arn, "${aws_s3_bucket.trust_store.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowElasticLoadBalancingRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.trust_store.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "trust_store" {
  bucket = aws_s3_bucket.trust_store.id
  policy = data.aws_iam_policy_document.trust_store.json
}

resource "aws_s3_object" "ca_bundle" {
  bucket       = aws_s3_bucket.trust_store.id
  key          = "ca-bundle.pem"
  content      = tls_self_signed_cert.ca.cert_pem
  content_type = "application/x-pem-file"

  depends_on = [aws_s3_bucket_versioning.trust_store]
}
