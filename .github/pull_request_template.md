<!-- Keep PRs small and single-purpose (~<400 lines changed — the SmartBear/Cisco
     effective-review ceiling). A focused PR with a real description is a senior signal. -->

## What
<!-- One or two sentences: what does this PR change? -->

## Why
<!-- The problem/decision behind it. Link the ADR if this PR embodies one. -->

## How
<!-- Key implementation notes / trade-offs a reviewer should know. -->

## Testing
<!-- How you verified it: `terraform validate`, `make up`, terratest, screenshots, etc. -->

## Impact / risk
<!-- Blast radius. What could this break? Anything a reviewer should double-check? -->

---
- [ ] Scoped to one purpose (~<400 lines)
- [ ] `terraform fmt` + `validate` pass locally (pre-commit)
- [ ] No secrets / real credentials committed
- [ ] Docs/ADR updated if this changes a decision
