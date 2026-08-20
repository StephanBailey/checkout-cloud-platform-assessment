locals {
  project_name  = "checkout-cloud-platform-assessment"
  function_name = "checkout_api"

  # ALB/target group names are capped at 32 characters, no underscores.
  short_name = "checkout-api"

  # TODO: placeholder per-environment CIDRs - adjust to your real IPAM plan.
  vpc_cidr_by_environment = {
    dev     = "10.10.0.0/16"
    nonprod = "10.20.0.0/16"
    prod    = "10.30.0.0/16"
  }
  # Falls back to a dummy-but-valid CIDR on an unrecognised workspace so this
  # doesn't crash before the "workspace_is_valid" check in terraform.tf can
  # report the actual problem.
  vpc_cidr = try(local.vpc_cidr_by_environment[terraform.workspace], "10.99.0.0/16")

  az_count = 2

  # TODO: replace with the real internal hostname clients will connect to.
  alb_domain_name = "checkout-api.${terraform.workspace}.internal.example.com"
}