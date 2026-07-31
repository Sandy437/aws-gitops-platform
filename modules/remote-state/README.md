# Module: `remote-state`

Provisions the Terraform remote-state backend: a versioned, encrypted, fully-private
S3 bucket for the state file plus a DynamoDB table for state locking.

## Usage

```hcl
module "remote_state" {
  source = "../../modules/remote-state"

  bucket_name     = "myorg-tfstate-dev"
  lock_table_name = "myorg-tf-locks-dev"
  tags = {
    Project = "aws-gitops-platform"
    Env     = "dev"
  }
}
```

## Bootstrap (the chicken-and-egg)

The bucket/table that *hold* remote state can't be stored in that state on first apply.
So this module is applied **once with a local backend**, then state is migrated:

```bash
# 1. apply with the default local backend to create the bucket + table
terraform init && terraform apply

# 2. add the s3 backend block pointing at the outputs, then migrate
terraform init -migrate-state
```

See [ADR-0001](../../docs/adr/0001-remote-state-backend.md) for why S3+DynamoDB over Terraform Cloud.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `bucket_name` | Globally-unique S3 bucket name for state | `string` | — (required) |
| `lock_table_name` | DynamoDB lock table name | `string` | `"terraform-locks"` |
| `force_destroy` | Allow bucket delete with objects present (dev only) | `bool` | `false` |
| `tags` | Tags applied to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | State bucket name (for backend config) |
| `bucket_arn` | State bucket ARN (for IAM scoping) |
| `lock_table_name` | Lock table name (for backend config) |

## Local testing (LocalStack)

Against LocalStack Community, S3 and DynamoDB are **real** (both supported), so this
module fully applies locally — unlike EKS/RDS which are substituted. See the root README's
fidelity table.
