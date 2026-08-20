variable "aws_region" {
  description = "AWS region to deploy the checkout infrastructure into."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like a valid AWS region, e.g. eu-west-1."
  }
}

variable "alb_allowed_ingress_cidrs" {
  description = "Internal CIDR ranges allowed to reach the ALB on 443. Placeholder - populate per environment."
  type        = list(string)
  default     = []
}

variable "alb_allowed_ingress_security_group_ids" {
  description = "Security group IDs of calling workloads allowed to reach the ALB on 443. Placeholder - populate per environment."
  type        = list(string)
  default     = []
}
