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

<!-- ✍️ YOU WRITE THIS (3-5 sentences, your voice) — the REAL reasoning:
     Why S3+DynamoDB over Terraform Cloud for THIS project? Tie it to what you want to
     demonstrate (operating the backend, locking mechanics, no SaaS dependency, staying $0
     and local). This paragraph is the "taste" signal a reviewer looks for — it must be
     your own judgment, not generic pros/cons. -->

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

<!-- ✍️ OPTIONAL — add any consequence YOU actually care about (e.g. cost, blast radius,
     what you'd change for a real multi-team prod backend). One honest line beats none. -->
