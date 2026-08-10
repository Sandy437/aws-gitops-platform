#!/usr/bin/env bash
# Seed the Flagship 1 build plan as GitHub issues, labels, and a milestone.
# Run once. Safe to re-run: label/milestone creation ignores "already exists".
#
# Requires: gh authenticated to Sandy437 with `repo` scope.
set -euo pipefail

REPO="Sandy437/aws-gitops-platform"
MILESTONE="Flagship 1 — AWS Terraform + GitOps platform"

echo "==> Creating labels (ignore 'already exists')"
# `task` must exist before any issue references it — GitHub does not auto-create labels.
gh label create "task" --repo "$REPO" --color "C5DEF5" --description "PR-sized unit of work from the build plan" 2>/dev/null || true
gh label create "week-1" --repo "$REPO" --color "1D76DB" --description "Foundations & safety gate" 2>/dev/null || true
gh label create "week-2" --repo "$REPO" --color "0E8A16" --description "Compute, data, envs, plan-in-CI" 2>/dev/null || true
gh label create "week-3" --repo "$REPO" --color "5319E7" --description "GitOps, cost guardrails, taste" 2>/dev/null || true
gh label create "adr" --repo "$REPO" --color "FBCA04" --description "Ships an architecture decision record" 2>/dev/null || true

echo "==> Creating milestone (ignore if exists)"
gh api -X POST "repos/$REPO/milestones" -f title="$MILESTONE" \
  -f description="14 atomic PRs over 3 weeks. See specs/01." >/dev/null 2>&1 \
  && echo "   milestone created" || echo "   milestone already exists (ok)"

# Helper: create an issue.  args: <week-label> <extra-labels-csv-or-empty> <title> <body>
mk() {
  local week="$1" extra="$2" title="$3" body="$4"
  local labels="task,$week"
  [ -n "$extra" ] && labels="$labels,$extra"

  # Skip if an issue with this exact title already exists — makes the script re-runnable.
  if gh issue list --repo "$REPO" --state all --search "\"$title\" in:title" \
       --json title --jq '.[].title' 2>/dev/null | grep -Fqx "$title"; then
    echo "   = exists, skipping: $title"
    return 0
  fi

  # Fail soft: a labelling problem on one issue must not abort the whole run.
  if gh issue create --repo "$REPO" \
      --title "$title" \
      --body "$body" \
      --label "$labels" \
      --milestone "$MILESTONE" >/dev/null 2>&1; then
    echo "   + $title"
  else
    echo "   ! FAILED (retrying without labels): $title"
    gh issue create --repo "$REPO" --title "$title" --body "$body" \
      --milestone "$MILESTONE" >/dev/null && echo "     + created unlabelled"
  fi
}

echo "==> Creating 14 build-plan issues"

# ---- Week 1 ----
mk week-1 "" "chore(repo): scaffold layout, pre-commit hooks, CODEOWNERS, PR/issue templates" \
"**PR #1** · Repo skeleton, .tool-versions, pre-commit (fmt/gitleaks), conventional-commit lint.

_Definition of done:_ README front door, LICENSE, Makefile help, templates in place.
✅ **Already shipped 2026-07-23.** Close this issue to reflect that."

mk week-1 adr "feat(backend): S3 + DynamoDB remote-state module (SSE, versioning, lock table)" \
"**PR #2** · Bootstrap remote-state module. Ships **ADR-0001** (remote state choice).

- Versioned + encrypted + fully-private S3 bucket
- PAY_PER_REQUEST DynamoDB lock table (hash key \`LockID\`)
- Document the bootstrap chicken-and-egg (\`-migrate-state\`)
- fmt + validate pass"

mk week-1 "" "ci(tf): static-analysis PR gate (fmt, validate, tflint, tfsec/Trivy, Checkov)" \
"**PR #3** · Fail on high-severity findings; justified \`#checkov:skip\` only with a reason.
Adds the CI badge to the README."

mk week-1 "" "feat(vpc): reusable VPC module (multi-AZ subnets, NAT toggle, flow logs) + terratest" \
"**PR #4** · First real infra module + a Terratest smoke test."

mk week-1 adr "feat(iam): least-privilege IAM + IRSA module with permissions boundary" \
"**PR #5** · Scoped roles/policies + permissions boundary. Ships **ADR-0006** (OIDC vs stored keys)."

# ---- Week 2 ----
mk week-2 "" "feat(local): kind + LocalStack one-command bootstrap (Makefile + docker-compose)" \
"**PR #6** · \`make up\` / \`make down\` — the reviewer's \$0 path."

mk week-2 adr "feat(cluster): EKS (cloud) / kind (local) cluster module behind one interface" \
"**PR #7** · Addon toggles (metrics-server, ingress). Ships **ADR-0005** (local fidelity strategy)."

mk week-2 "" "feat(rds): RDS Postgres module (free-tier sizing) + local Postgres container fallback" \
"**PR #8** · Real RDS on cloud; containerised Postgres locally (LocalStack Community has no RDS)."

mk week-2 "" "feat(ingress): ALB via AWS LB Controller (cloud) / ingress-nginx (local)" \
"**PR #9** · One ingress contract, two backends."

mk week-2 adr "feat(envs): dev/prod composition roots with isolated state keys" \
"**PR #10** · Thin roots consuming modules. Ships **ADR-0002** (directory-per-env vs workspaces)."

mk week-2 "" "ci(plan): per-env terraform plan vs LocalStack, sticky PR comment + JSON artifact" \
"**PR #11** · plan-in-CI matrix over dev/prod; \`apply\` gated on protected env. Adds plan-gate badge."

# ---- Week 3 ----
mk week-3 adr "feat(argocd): install ArgoCD via Helm + root app-of-apps" \
"**PR #12** · Self-managing root; sync-waves for CRDs/namespaces. Ships **ADR-0007** (app-of-apps vs ApplicationSet) + **ADR-0003** (repo split)."

mk week-3 "" "feat(gitops): sample microservice + ApplicationSet (app-repo vs config-repo split)" \
"**PR #13** · Go service with /healthz /readyz /metrics; automated tag-bump PR into config repo."

mk week-3 "" "feat(cost): Infracost in CI + AWS Budget alarm + nuke/teardown script" \
"**PR #14** · The guardrails that make the real-AWS path safe. Final DESIGN.md + diagram + demo GIF pass."

echo ""
echo "==> Done. View them:  gh issue list --repo $REPO"
