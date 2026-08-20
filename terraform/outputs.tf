output "vpc_id" {
  description = "ID of the checkout VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets shared by the ALB, Lambda, and VPC endpoints."
  value       = aws_subnet.private[*].id
}

output "alb_dns_name" {
  description = "Internal DNS name of the ALB. Resolvable only from within the VPC/connected network."
  value       = aws_lb.checkout_api.dns_name
}

output "alb_arn" {
  description = "ARN of the checkout API ALB."
  value       = aws_lb.checkout_api.arn
}

output "lambda_function_name" {
  description = "Name of the checkout API Lambda function."
  value       = aws_lambda_function.checkout_api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the checkout API Lambda function."
  value       = aws_lambda_function.checkout_api.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Logs group for the Lambda function."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "trust_store_bucket_name" {
  description = "S3 bucket holding the mTLS CA trust bundle."
  value       = aws_s3_bucket.trust_store.id
}

output "alb_access_logs_bucket_name" {
  description = "S3 bucket receiving ALB access logs."
  value       = aws_s3_bucket.alb_access_logs.id
}

output "alarms_sns_topic_arn" {
  description = "SNS topic that CloudWatch alarms notify (stub - no subscription configured)."
  value       = aws_sns_topic.alarms.arn
}

output "github_actions_role_arn" {
  description = "OIDC-assumable IAM role ARN for this environment. Set as the AWS_ROLE_ARN GitHub Environment variable."
  value       = aws_iam_role.github_actions.arn
}
