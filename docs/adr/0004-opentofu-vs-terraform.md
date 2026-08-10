# ADR-0004: Run OpenTofu in CI (keeping Terraform compatibility)

- **Status:** Accepted
- **Date:** 2026-08-10
- **Deciders:** Sandy437

## Context

In August 2023 HashiCorp relicensed Terraform from MPL-2.0 to the Business Source
License (BSL). The community fork **OpenTofu** (Linux Foundation, MPL-2.0) continues
under the original open-source licence and remains configuration-compatible.

Two practical consequences forced a decision in this repo:

1. **Licensing.** Homebrew pins `terraform` at **1.5.7** — the last MPL-licensed
   release — so "just install terraform" gives you a version that is nearly three
   years behind. Newer Terraform is BSL-licensed.
2. **Testing.** The modern module-testing framework (`.tftest.hcl` files, `run`
   blocks, `assert` conditions) landed in **Terraform 1.6**, i.e. after the relicense.
   On 1.5.7 the `test` command is the old experimental one, which warns in its own
   help output that it is "primarily for research purposes" and "likely to change in
   breaking ways." Testing modules properly on 1.5.7 is therefore not viable.

The alternative for testing was **Terratest** (Go). That means adding a Go toolchain,
a `go.mod`, and Go test files to an otherwise HCL repo.

## Decision

**CI runs OpenTofu (`tofu`), and modules are tested with the native `.tftest.hcl`
framework.** Configuration stays written so that Terraform users can consume these
modules unchanged — no OpenTofu-only syntax, and `required_version` stays permissive.

Rationale: OpenTofu keeps the project fully open-source-licensed, gives access to the
current native test framework without adding a second language toolchain, and is a
drop-in for the `terraform` CLI. A reviewer can run the tests with either binary.
Terratest is the more widely recognised name and better for complex integration
scenarios, but for asserting module logic (subnet maths, NAT toggles, tag propagation)
it is a heavier dependency than the problem needs — and a Go test suite in an HCL
repo raises the barrier for anyone wanting to run it.

## Alternatives considered

- **Terraform 1.5.7 + Terratest (Go).** Industry-recognised, powerful, cloud-integration
  friendly. Rejected for now: adds a Go toolchain and module to an HCL-only repo, and
  leaves the config pinned to a three-year-old CLI.
- **Terraform >= 1.6 (BSL).** Gives the native test framework, but adopts the BSL for a
  public portfolio project when a licence-clean, compatible alternative exists.
- **Stay on 1.5.7 with no module tests.** Rejected: untested modules are exactly the
  "junior" signal this repo is built to avoid.

## Consequences

- CI installs OpenTofu via `opentofu/setup-opentofu`; local development works with
  either `tofu` or `terraform` (the commands are argument-compatible).
- `.tool-versions` records both binaries so intent is explicit.
- Module tests live in `tests/*.tftest.hcl` next to each module and run in CI.
- **Fidelity note:** tests use `command = plan` so they assert configuration logic
  without creating real infrastructure — no credentials, no cost, and they run in a
  fork's CI.
- If a future need is genuinely integration-shaped (real VPC reachability, IRSA token
  exchange), Terratest can be added alongside rather than instead — this ADR does not
  rule it out.
