# Security groups only - the ALB/listener resources that consume
# aws_security_group.alb live in alb.tf.
resource "aws_security_group" "alb" {
  name        = "${local.short_name}-${terraform.workspace}-alb"
  description = "Internal ALB - inbound mTLS HTTPS from approved sources only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cidr" {
  for_each = toset(var.alb_allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Approved internal CIDR"
}

# Production alternative:
#
# data "aws_security_group" "calling_workload" {
#   for_each = toset(var.calling_workload_names)
#
#   filter {
#     name   = "tag:Name"
#     values = [each.value]
#   }
# }
#
# ...then reference data.aws_security_group.calling_workload[*].id below
# instead of var.alb_allowed_ingress_security_group_ids.
resource "aws_vpc_security_group_ingress_rule" "alb_from_sg" {
  for_each = toset(var.alb_allowed_ingress_security_group_ids)

  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = each.value
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Approved calling workload security group"
}

resource "aws_security_group" "lambda" {
  name        = "${local.short_name}-${terraform.workspace}-lambda"
  description = "Lambda ENIs - no inbound, egress limited to the VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-lambda"
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_vpc_endpoints" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Secrets Manager / CloudWatch Logs interface endpoints"
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.short_name}-${terraform.workspace}-vpc-endpoints"
  description = "Secrets Manager / CloudWatch Logs interface endpoints - inbound HTTPS from the Lambda function only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.short_name}-${terraform.workspace}-vpc-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_lambda" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Lambda function"
}
