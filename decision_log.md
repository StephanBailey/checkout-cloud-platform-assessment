# Decision log

## AI Usage

I am creating the architecture, repo structure, and technical decision log first, and then I am using Claude to accelerate implementation, prompting it one file at a time and reviewing each suggestion against my intended architecture and AWS documentation before reviewing and accepting.

## Assessment Scope

I am prioritising the core networking, compute, security, terraform, and CI/CD requirements. I will document what I would have done if I run out of time for the assessment.
I am mirroring what I have implemented previously:

1. Repo structure
2. API Gateway schema for validation (API Gateway has been replaced with ALB but am retaining schema for Lambda)

## mTLS

API Gateway mTLS constraint: mTLS is associated with an API Gateway custom domain rather than the generated execute-api hostname. The default execute-api endpoint should therefore be disabled to prevent bypassing mTLS. Need to verify whether AWS supports mTLS on private API Gateway custom domains or whether an alternative architecture is required.
Reading further, I have found that Application Load Balancers can implement mTLS. The brief expects mTLS at the API layer, however, this solution fulfils the mTLS requirement.

https://docs.aws.amazon.com/elasticloadbalancing/latest/application/mutual-authentication.html

I have read further and found that mTLS is *not* possible using a private API Gateway. https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mutual-tls.html

https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mutual-tls.html#:~:text=Mutual%20TLS%20isn%27t%20supported%20for%20private%20APIs.

With this, this solidifies my decision to use mTLS on the ALB. The downstream API needs to be restricted so that it can't be invoked directly and bypass the ALB.

## Load Balancer

Lambda does not require an LB for scaling as it horizontally scales automatically. It is also not required to operate within a VPC. ALBs are the only load balancers that support the Lambda target type: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html
The ALB is an ingress/security requirement, and not a Lambda scaling requirement.
ALB does not send logs to CloudWatch, and instead sends to S3 - this goes against the brief.

Edit - I have just found that since 23/07/2026, ALB supports sending logs to CloudWatch: https://aws.amazon.com/about-aws/whats-new/2026/07/amazon-cloudwatch-logs/

S3 access for ALB logs remains free, whereas CloudWatch delivery is billed as vended logs. "ALB logs are charged as vended logs when delivered to CloudWatch Logs and Data Firehose, while delivery to Amazon S3 is free (Parquet conversion is charged at $0.035/GB - N. Virginia)." I will keep as S3.

## Private Keys/Certificate Material

Private keys and certificate material will be stored in Secrets Manager due to it providing encryption at rest using KMS, and will be controlled via IAM. The brief allows the use of Terraform's `tls` provider, so that the generated keys will also exist in state. A way to mitigate exposure is to ensure the backend (in this case S3) is encrypted, locked down using IAM and use state locking. I have experience using DynamoDB, but I read that this is no longer necessary. DynamoDB state locking is now deprecated and we can enable state locking just using S3.
S3 is used for the ALB Trust store. The object fetch from S3 is performed by the Elastic Load Balancing control plane, which is AWS-managed infrastructure, and doesn't touch the VPC route table. So using a gateway endpoint for S3 wouldn't work in this case and isn't necessary. The brief mentions that it is required, however, I don't want to add infrastructure for the sake of it. If when building it out I discover that I require it, I will add it.
In production I would use ACM Private CA - so the key never exists outside of AWS, and therefore wouldn't be held in state. For the purposes of this exercise, the S3 bucket containing the state will be scoped using least privilege.

> Enabling S3 State Locking
>
> To enable S3 state locking, use the following optional argument:
>
> - `use_lockfile` - (Optional) Whether to use a lockfile for locking the state file. Defaults to false.

https://developer.hashicorp.com/terraform/language/backend/s3#:~:text=State%20locking%20is,be%20configured%20simultaneously.

## Deploying Terraform

The goal is to make it easy to run a plan, apply, and a destroy locally, make it easy to run, and also any tests are run easily. To facilitate this, I will use a Taskfile which will be split as follows:

**Terraform tasks:**

- `terraform init`
- `terraform validate`
- `terraform plan`
- `terraform apply`
- `terraform test`

**Python tasks:**

- `pytest` (for unit tests) - integration tests will be confined to the workflow

The Taskfile should switch to the appropriate workspace depending on the environment (dev, nonprod, prod). Each task should make it easier to run Terraform commands, based on what I have done previously.
These tasks will then be used in the Terraform workflow to ensure parity between deploying locally and within the pipeline. The reason for this is if we need to test anything in dev without going through the pipeline, this makes it easier for us.

Local execution is dependent on using a role operating under the principle of least privilege. CI itself uses GitHub OIDC and short-lived AWS credentials.

- `task.yml` workflow for inputs
- `deploy.yml` for taking in those inputs and deploying to an account
- An OIDC role to be used - I read recently that the structure of the role has been changed to incorporate IDs: `repo:owner@1234/repo-name@5678:ref:refs/heads/main`

  https://www.linkedin.com/posts/andmoredev_heads-up-if-youre-using-github-actions-share-7494165385890430976-CZgb

The cut-off point for repos was 15-07-2026.

## Backend

Note: The S3 bucket would have to be created before this Terraform is deployed in order to use it as a backend for Terraform state.

## KMS keys

Going with AWS-owned keys (AWS-managed keys still have their place, but aren't the lowest-overhead option where an owned-key tier exists - https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/key-management.html#key-management-types) as there is less overhead: customer-managed keys cost $1 a month, and unlike AWS-managed keys, AWS-owned keys have no cost associated with them.

## Networking

No need for NACLs here as they are stateless, and would require implementing both inbound and outbound rules, whereas security groups are stateful. It would make more sense to use a NACL if the service calling the ALB was public and needed to call the private endpoint. The default "allow-all" NACL is left as is.
Lambda is VPC-attached despite not needing to be for scaling. It is private to ensure that calls to Secrets Manager, CloudWatch Logs, and SSM Parameter Store stay off the public internet, via VPC interface endpoints.

## Logging

I will not be implementing centralised logging as I don't have the time, but if I were going to, I would use Amazon CloudWatch Logs data centralisation: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatchLogs_Centralization.html
This only works for new logs, not historic logs, and as we are standing up new infrastructure, this fits with what we are doing.

## Costs

I will ask Claude to help me figure out costs once I have finished creating the infrastructure.
