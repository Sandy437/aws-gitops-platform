# ADR-0001: Remote state on S3 + DynamoDB (not Terraform Cloud, not local)

- **Status:** Accepted
- **Date:** 2026-07-24
- **Deciders:** Sandy437

## Context

Terraform needs somewhere to store state and a way to prevent two applies from
running at once (locking). The three realistic options for this project:

1. **Local state** (`terraform.tfstate` on disk) — no locking, easily lost, can't be shared.
2. **Terraform Cloud / HCP** — managed backend with locking, UI, and run history.
3. **Self-managed S3 + DynamoDB** — S3 stores the state file (versioned/encrypted),
   DynamoDB provides a lock via a `LockID` item.

Constraints for this repo: it must run **free and fully local** (LocalStack Community
supports both S3 and DynamoDB), and it should demonstrate that I can *operate the backend
myself* rather than delegate it to a SaaS.

## Decision

Use **self-managed S3 + DynamoDB** for remote state.

I chose to run my own state backend on S3 and DynamoDB rather than use Terraform Cloud because I want this project to be fully self-contained and free to run, Terraform Cloud is a managedSaaS that can't run against LocalStack, so it would break the "$0, entirely local" goal. More importantly, self-managing the backend shows I understand the mechanics I'd otherwise be     delegating: S3 versioning as the recovery path for a bad state write, and a DynamoDB item as the lock that stops two applies from racing. It's also what most AWS teams
I've worked with actually use, so it's the honest thing to demonstrate. For a real multi-team production backend I'd reach for a KMS customer-managed key and cross-region replication;
for a portfolio backend, AES256 plus versioning is a deliberate stopping point, not an oversight.

## Alternatives considered

- **Terraform Cloud / HCP:** locking + run history out of the box, but adds a SaaS
  dependency, can't run against LocalStack, and hides the backend mechanics I want to show.
- **Local state:** disqualified — no locking, no sharing, trivially lost; the anti-pattern
  this whole module exists to avoid.

## Consequences

- I own the backend lifecycle, including the **bootstrap chicken-and-egg**: the bucket/table
  are created with a local backend first, then `terraform init -migrate-state` moves state in.
- State locking depends on the DynamoDB table's hash key being named exactly `LockID`.
- **Non-goal (for now):** KMS-CMK encryption and cross-region state replication — AES256 +
  versioning is enough for a portfolio backend; noted so the omission reads as a decision, not a gap.
- **CI flags this, and that is expected.** Trivy `AWS-0132` (HIGH) fails on SSE-S3 and wants a
  customer-managed KMS key. It is suppressed at the resource in `modules/remote-state/main.tf`
  with a reason and an expiry (`exp:2027-02-01`), so the deferral cannot rot silently — after
  that date CI fails again and forces a re-decision. The follow-up is an optional `kms_key_arn`
  input that switches the bucket to `aws:kms` when supplied and stays on AES256 when not,
  keeping the local $0 path unchanged.

<!-- ✍️ OPTIONAL — add any consequence YOU actually care about (e.g. cost, blast radius,
     what you'd change for a real multi-team prod backend). One honest line beats none. -->
