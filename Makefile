# aws-gitops-platform — task runner.
# Targets are added PR-by-PR (see specs/01 build plan). `help` is the front door.

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- Local, $0 path (implemented in later PRs) ---------------------------------
.PHONY: up
up: ## (PR #6+) Boot kind + LocalStack, bootstrap state, apply, install ArgoCD
	@echo "Not implemented yet — arrives in PR #6 (local bootstrap)."

.PHONY: down
down: ## Tear everything down (no containers, no cost)
	@echo "Not implemented yet — arrives in PR #6."

.PHONY: demo
demo: ## (PR #13+) Port-forward the sample service and show a git-revert rollback
	@echo "Not implemented yet — arrives in PR #13."

# --- Optional real-AWS path (guarded; implemented in PR #14) --------------------
.PHONY: aws-up
aws-up: ## (PR #14) Apply to real AWS free-tier (prompts for confirmation)
	@echo "Not implemented yet — arrives in PR #14. Real AWS incurs hourly cost."

.PHONY: aws-nuke
aws-nuke: ## (PR #14) Destroy real-AWS resources + sweep orphans
	@echo "Not implemented yet — arrives in PR #14."
