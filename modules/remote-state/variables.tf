variable "bucket_name" {
  description = "Globally-unique name for the S3 bucket that holds Terraform remote state."
  type        = string

  validation {
    # S3 bucket naming rules: 3-63 chars, lowercase letters/numbers/hyphens/dots.
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase alphanumeric, hyphens or dots."
  }
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  type        = string
  default     = "terraform-locks"
}

variable "force_destroy" {
  description = <<-EOT
    Allow the state bucket to be destroyed even if it still contains objects.
    Keep FALSE for anything resembling prod — deleting a state bucket is catastrophic.
    Only set TRUE for throwaway local/dev backends.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
