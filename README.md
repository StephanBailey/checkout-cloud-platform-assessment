# checkout-cloud-platform-assessment

# Documentation referenced 

[MTLS API Gateway Lambda](https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mutual-tls.html)

"By default, clients can invoke your API by using the execute-api endpoint that API Gateway 
generates for your API. To ensure that clients can access your API only by using a custom domain 
name with mutual TLS, disable the default execute-api endpoint. To learn more, 
see Disable the default endpoint for REST APIs."

Contrary to what the task asks from me, execute-api would bypass the MTLS requirement, 
so I will disable it. mTLS is associated with a custom domain name, so I will create a custom domain name and 
associate it with the API Gateway.

# Infrastructure Diagram

![Checkout infrastructure architecture](images/checkout_infra.jpg)

(Previous version is still available in images/)

# Encryption and Key Management

Before writing any of the encryption-related resources, I'd already researched the difference
between AWS-owned keys, AWS-managed keys, and customer-managed KMS keys, and the cost/overhead
trade-off between them - this wasn't something I worked out mid-build, it informed the design
from the start.

- **S3 (trust-store bucket and ALB access-logs bucket)**: SSE-S3 (`AES256`). This uses an
  AWS-owned key - it never appears in the account's KMS console, there's no monthly fee, and
  critically there's no per-request KMS API charge either, because the encryption happens
  entirely inside the S3 service rather than through a customer-facing KMS call. For buckets that
  don't need custom key policies, cross-account grants, or independent audit/rotation control,
  this is strictly less overhead than SSE-KMS for the same practical protection.
- **Secrets Manager (CA private key, test client certificate)**: the default AWS-managed key
  (`aws/secretsmanager`), i.e. no `kms_key_id` specified. Secrets Manager has no AWS-owned-key
  tier the way S3 does - every secret is encrypted through KMS one way or another - so the
  AWS-managed key is the lowest-overhead option actually available for this service. It still
  costs nothing per month; only the customer-managed tier adds the ~$1/month/key charge.
- **CloudWatch Logs**: left on AWS's default encryption at rest, no explicit KMS key configured.

Net effect: this build provisions **no customer-managed KMS key**. That's a deliberate decision,
not an oversight - nothing here needs a custom key policy, cross-account key sharing, or
independent key rotation scheduling at this stage. I would introduce a customer-managed key if a
future requirement needed one of those specifically (e.g. sharing decrypt access with another
account, or an audit requirement for customer-controlled rotation), and would scope its key
policy narrowly to the principals that actually need it rather than defaulting to broad access.

# Setup, Deployment, and Teardown

## Prerequisites

- Terraform >= 1.10.0, [Task](https://taskfile.dev) (`go-task`), Python >= 3.13.
- An AWS credential with enough privilege to bootstrap the account (see below) - day-to-day
  local usage should use a role scoped to least privilege, not this bootstrap credential.

## One-time account bootstrap (chicken-and-egg problem)

Two things in this design can't be created by the pipeline that depends on them, so they must be
created once, out-of-band, before the first `terraform apply` in a given account:

1. **The Terraform state bucket** referenced in `terraform/terraform.tf` (`backend "s3"`) doesn't
   exist yet - it must be created manually (versioned, encrypted) before `terraform init` will
   succeed. State locking uses S3's native `use_lockfile` support, so no separate DynamoDB table
   is needed.
2. **The GitHub Actions OIDC provider and deploy role** (`terraform/oidc.tf`) can't be assumed by
   a CI run to create themselves. The first `terraform apply` per account has to run under a
   human/admin credential, not the CI role. After that first apply, set the resulting
   `github_actions_role_arn` output as the `AWS_ROLE_ARN` variable on that environment's GitHub
   Environment, and CI can take over from there.

## Local workflow

All commands go through the Taskfile so local runs and CI stay identical:

```
task tf:plan ENV=dev
task tf:apply ENV=dev
task py:test
task py:lint
```

`ENV` defaults to `dev` and is validated against `dev`/`nonprod`/`prod`.

## CI/CD workflow

- Merging to `main` deploys to `dev` first - no approval gate, this is the lowest-risk
  environment - then `nonprod`, then `prod`, in sequence. `nonprod` and `prod` each only proceed
  if the corresponding GitHub Environment has a required-reviewer approve it. That protection
  rule has to be configured in the repo's Settings -> Environments; it isn't something a workflow
  YAML file can declare on its own.
- Opening a pull request runs a `plan` against `dev` for a quick sanity check, without applying
  anything.
- There's a single trunk (`main`) - no separate long-lived `dev` branch.

## Teardown

```
task tf:destroy ENV=dev
task tf:destroy ENV=nonprod
task tf:destroy ENV=prod
```

Both S3 buckets (`trust_store`, `alb_access_logs`) are created with `force_destroy = true`
specifically so `terraform destroy` can remove them even with objects still inside (the CA
bundle, and any accumulated ALB access-log files) - without it, destroy would fail on a
non-empty bucket and need a manual empty-then-delete step first.

# AI Usage and Critique

I created the architecture, the diagram above, the repo structure, and the technical decision
log first. Claude was then used only to accelerate implementation, prompted one Terraform/Python
file at a time, with each suggestion reviewed against my intended architecture and AWS
documentation before being accepted. I did not let it design the system; I directed it file by
file and rejected or corrected anything that didn't match a decision I'd already made or
contradicted the brief.

## Representative prompts

- "Start by telling me which file you think we should implement first and why. Do not generate
  multiple files at once."
- One-file-at-a-time direction throughout (e.g. "Let's go with variables.tf", "Let's go with
  network.tf", "Let's go to security.tf now") - I controlled build order, not the assistant.
- "I would prefer the project name to be part of the locals.tf. This would be used across
  environments, so we don't need to pass this in as a variable" - correcting a variable/local
  split I disagreed with.
- Pasting the actual assessment brief text mid-build to force a check of earlier assumptions
  against the real grading criteria, which surfaced at least one direct contradiction (see below).
- "Even though the brief says to add this gateway endpoint, I don't think we should, as it isn't
  in use, and I don't want to create unnecessary infra" - explicit pushback against blindly
  satisfying a brief line where I judged it added no real value.
- "Is any of my Python code used in the upstix api relevant to how we use powertools here for
  tracing and logs?" - pointing the assistant at my own existing code so new code matched my
  established style instead of inventing a different one.
- "On line 41, you can set default values in a .get method e.g. .get('body', {})" - a direct
  code-style correction.
- Told it explicitly that decision rationale must never be written into code comments - all
  reasoning had to be surfaced to me in chat so it landed in this document, in my own words,
  since I'm the one who has to defend it in interview.
- "I want to use a pyproject.toml rather than a requirements.txt." - a packaging preference,
  asked separately from the gating request below rather than bundled in.
- "I want a gate between dev, nonprod, and prod. So when dev is merged into main, someone has to
  approve to go to nonprod, and then the same from nonprod to prod."
- "Why are we using unittest and not pytest?" - queried a design choice rather than accepting it;
  the answer was that `unittest.mock` is just the standard library's mocking toolkit used from
  inside pytest-style tests, not `unittest.TestCase` - but I asked rather than assumed either way.
- "Let's add some unit tests for Python."
- "Let's also add some sensible outputs."
- "Can you also add the KMS decision to the README.md, explicitly stating that I had researched
  AWS-owned keys and the tradeoffs beforehand."
- "Can you add number 9 [setup/deployment/teardown instructions] to the README.md as well."
- "There is one correction I want to make. Merging to main should deploy to dev. Then we have
  gates for nonprod and prod. You'll be able to see this in
  ~/_git/<my_repo that I referenced>" - corrected the promotion flow by pointing at an
  existing real workflow of mine, rather than accepting the assistant's first structure.

## Critique of the output

- **Over-permissive IAM, caught but not yet fixed**: the GitHub Actions OIDC deploy role
  (`terraform/oidc.tf`) was attached to `AdministratorAccess` as a placeholder, with only a
  `TODO` comment noting it should be scoped down. That's exactly the kind of over-permissive
  default an assistant reaches for under time pressure, and it needs replacing with a policy
  scoped to the specific services this stack manages before this could go anywhere near a real
  account.
- **Unverified/incorrect specifics in an earlier draft**: `lambda.tf` already contained a
  `python3.14` runtime and a hardcoded Powertools Lambda layer ARN before this pass. Neither was
  safe to trust as-is - `python3.14` support requires an AWS provider version we weren't pinned
  to, and the specific layer ARN/version was unverifiable without checking AWS's docs directly.
  I had it verify both against live sources rather than accept them, and switched the layer
  reference to a dynamic SSM parameter lookup instead of a hardcoded ARN so it can't silently go
  stale.
- **No public endpoint was ever proposed** - the ALB stayed internal-scheme with no IGW/NAT
  throughout, which I verified rather than assumed.
- **Non-standard branching pattern suggested**: the first version of the promotion pipeline
  invented a separate long-lived `dev` branch that auto-deployed on push, with `main` only
  handling `nonprod`/`prod`. That's not how I actually work - a single trunk (`main`) with
  `dev`/`nonprod`/`prod` promoted in sequence from the same merge is the real pattern, and I had
  to point it at an existing workflow of mine to get it corrected rather than it inferring my
  actual convention unprompted.
- **Non-standard pattern check**: security group rules use the newer split
  `aws_vpc_security_group_ingress_rule`/`egress_rule` resources rather than legacy inline
  ingress/egress blocks, and the S3 bucket policy for ALB access logs uses the current
  `logdelivery.elasticloadbalancing.amazonaws.com` service-principal method rather than the
  deprecated per-region-account-ID legacy policy - both checked against current AWS docs rather
  than assumed from training data.
- **A claimed external fact was checked, not trusted**: before writing the OIDC trust policy I
  had it verify a claim (from a LinkedIn post) that GitHub had changed its OIDC subject-claim
  format to include immutable numeric IDs. It was true, but only for repos created after
  2026-07-15 - it then pulled this repo's real owner/repo IDs via the GitHub API rather than
  guessing, which is what's in the trust condition now.
- **Recurring correction**: it kept writing decision rationale into Terraform/Python comments
  ("why we chose X"). I had all of that stripped out and required it be surfaced to me in chat
  instead, since this document - not the code - is what I need to defend.