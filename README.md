# aws-gitops-platform

<!-- Badges land in PR #3 (CI) and PR #11 (plan gate). Leave the placeholders. -->
![CI](https://img.shields.io/badge/ci-pending-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)
![IaC](https://img.shields.io/badge/IaC-Terraform%20%7C%20OpenTofu-7B42BC)

> This project consists of a reusable Terraform/OpenTofu module library and GitOps delivery pipeline for a
> Kubernetes (k8's) platform on AWS, with remote-state locking, policy-gated CI, and ArgoCD. This project can
> run/runs **entirely locally for $0** on kind, and has an optional, cost-guarded path to real AWS also exists for an excercise or usecases against actual services.

---

## ⚠️ What this is (and honestly is not)

The whole thing is reproducible on a laptop. Being explicit about where the local version differs from real AWS is deliberate — that honesty is the point of the table below.

| Component | Local (default, $0) | Real AWS (optional, guarded) |
|-----------|---------------------|------------------------------|
| Kubernetes | **real** — kind cluster | EKS |
| Remote state (S3 + DynamoDB lock) | **real** — served by LocalStack | real S3 + DynamoDB |
| VPC / networking | `plan`/`validate` only — LocalStack Community does not truly implement it | real |
| RDS Postgres | **substituted** — local Postgres container | real RDS (free-tier sizing) |
| IRSA / pod identity | **documented-only** — no OIDC provider on kind | real IRSA |
| Ingress | ingress-nginx + port-forward | ALB via AWS LB Controller |

> **LocalStack Community does not provide EKS or RDS** (Pro-only). That is *why* the cluster
> module falls back to kind and RDS to a container locally — see `docs/adr/` once written.
> The default reviewer experience is always the $0 local path.

---

## Quickstart (local, $0)

> **First run is ~15–30 min** (image pulls + ArgoCD bootstrap), not "5 minutes" — under-promising on purpose.

```bash
make help     # list targets
make up       # (PR #6+) boots kind + LocalStack, bootstraps state, applies, installs ArgoCD
make demo     # (PR #13+) port-forwards the sample service, shows a git-revert rollback
make down     # tears everything down — no containers, no cost
```

Prerequisites: Docker/Colima, `kind`, `kubectl`, `helm`, `terraform` **or** `tofu`, `make`.
Pinned versions in [`.tool-versions`](.tool-versions).

## Optional real-AWS path (costs a few $, destroy same day)

> **EKS control plane, NAT gateways, and ALB are hourly and NOT free-tier.** Spin up →
> screenshot → `make aws-nuke` the same day. A Budget alarm + Infracost guard this path.

```bash
make aws-up    # (PR #14) prompts for confirmation; uses GitHub OIDC / a scoped local profile
make aws-nuke  # terraform destroy + orphan sweep
```

---

## Repo layout

```
modules/        reusable Terraform modules (vpc, iam, cluster, rds, ingress)
environments/   thin composition roots (dev, prod) with isolated state keys
scripts/        bootstrap + nuke + metrics helpers
.github/        CI workflows + PR template
docs/adr/       architecture decision records (the "why", in my voice)
```

## Decisions & trade-offs

See [`docs/adr/`](docs/adr/) and `DESIGN.md` (added in PR #14). Each ADR defends a position and
names what was rejected — that's where the real engineering judgment lives.

## Roadmap / sibling repos

<!-- ✍️ Fill in once the sibling repos exist: Backstage IDP, observability/SLOs, supply-chain. -->

## License

[MIT](LICENSE)
