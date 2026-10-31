# ==============================================================================
# DevOps Skill - Unified Automation & Quality Gate Makefile
# Enterprise-grade standards for Containers, Kubernetes, Helm, IaC, and CI/CD
# ==============================================================================

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# ------------------------------------------------------------------------------
# Environment & Tooling Resolution
# ------------------------------------------------------------------------------
ROOT_DIR   := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
HAS_DOCKER := $(shell command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && echo true || echo false)

# Docker Fallback Images
IMAGE_HADOLINT    ?= hadolint/hadolint:latest
IMAGE_KUBECONFORM ?= ghcr.io/yannh/kubeconform:latest
IMAGE_SHELLCHECK  ?= koalaman/shellcheck:latest
IMAGE_HELM        ?= alpine/helm:latest
IMAGE_TERRAFORM   ?= hashicorp/terraform:latest
IMAGE_YAMLLINT    ?= cytopia/yamllint:latest
IMAGE_ACTIONLINT  ?= rhysd/actionlint:latest
IMAGE_MARKDOWNLINT?= tmknom/markdownlint:latest

# Target Directories
TF_DIR            ?= templates/terraform
K8S_DIRS          ?= templates/kubernetes templates/kustomize/base
HELM_CHART_DIR    ?= templates/helm/app-chart
CONTAINERS_DIR    ?= templates/containers
SCRIPTS_DIR       ?= scripts

# Colors
BOLD   := \033[1m
RESET  := \033[0m
GREEN  := \033[0;32m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
YELLOW := \033[0;33m
RED    := \033[0;31m

.PHONY: all help lint validate validate-k8s validate-tf validate-helm \
        lint-docker lint-shell lint-yaml lint-md lint-actions scan-secrets \
        audit-image test-all fmt fmt-tf

# ==============================================================================
# High-Level Orchestration Targets
# ==============================================================================

## all: Execute the full unified validation suite
all: test-all

## test-all: Run all automated linters, schema checks, and security scans
test-all:
	@chmod +x $(SCRIPTS_DIR)/validate-all.sh
	@./$(SCRIPTS_DIR)/validate-all.sh

## lint: Execute all source linters (yamllint, markdownlint, actionlint, hadolint, shellcheck)
lint: lint-yaml lint-md lint-shell lint-docker lint-actions
	@printf "$(GREEN)$(BOLD)✔ All linters completed successfully.$(RESET)\n"

## validate: Execute all structural and schema validators (K8s, Terraform, Helm)
validate: validate-k8s validate-tf validate-helm
	@printf "$(GREEN)$(BOLD)✔ All schema validations completed successfully.$(RESET)\n"

# ==============================================================================
# Schema & Specification Validation Targets
# ==============================================================================

## validate-k8s: Validate Kubernetes manifests and CRD structure using kubeconform
validate-k8s:
	@printf "$(BLUE)$(BOLD)▶ Validating Kubernetes manifests ($(K8S_DIRS))...$(RESET)\n"
	@if command -v kubeconform >/dev/null 2>&1; then \
		kubeconform -summary -strict -ignore-missing-schemas $(K8S_DIRS); \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_KUBECONFORM) \
			-summary -strict -ignore-missing-schemas $(K8S_DIRS); \
	else \
		$(SCRIPTS_DIR)/k8s-dry-run-validate.sh templates/kubernetes; \
	fi

## validate-tf: Check Terraform / OpenTofu formatting and syntax without altering files
validate-tf:
	@printf "$(BLUE)$(BOLD)▶ Checking Terraform formatting & syntax ($(TF_DIR))...$(RESET)\n"
	@if command -v terraform >/dev/null 2>&1; then \
		terraform fmt -check -diff $(TF_DIR); \
	elif command -v tofu >/dev/null 2>&1; then \
		tofu fmt -check -diff $(TF_DIR); \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_TERRAFORM) \
			fmt -check -diff $(TF_DIR); \
	else \
		printf "$(YELLOW)⚠ Neither terraform, tofu, nor docker available to validate Terraform.$(RESET)\n"; \
	fi

## validate-helm: Lint Helm chart templates and validate values schema
validate-helm:
	@printf "$(BLUE)$(BOLD)▶ Linting Helm chart ($(HELM_CHART_DIR))...$(RESET)\n"
	@if command -v helm >/dev/null 2>&1; then \
		helm lint $(HELM_CHART_DIR); \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_HELM) \
			lint $(HELM_CHART_DIR); \
	else \
		printf "$(YELLOW)⚠ Neither helm nor docker available to lint Helm chart.$(RESET)\n"; \
	fi

# ==============================================================================
# Source Code Linting Targets
# ==============================================================================

## lint-docker: Check Dockerfile best practices and security with hadolint
lint-docker:
	@printf "$(BLUE)$(BOLD)▶ Linting Dockerfiles with hadolint...$(RESET)\n"
	@FILES=$$(find $(CONTAINERS_DIR) -name "Dockerfile*" 2>/dev/null); \
	if [ -z "$$FILES" ]; then \
		printf "$(YELLOW)⚠ No Dockerfiles found in $(CONTAINERS_DIR)$(RESET)\n"; \
	elif command -v hadolint >/dev/null 2>&1; then \
		hadolint --ignore DL3008 --ignore DL3013 --ignore DL3066 $$FILES; \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_HADOLINT) \
			/bin/hadolint --ignore DL3008 --ignore DL3013 --ignore DL3066 $$FILES; \
	else \
		printf "$(YELLOW)⚠ Neither hadolint nor docker available.$(RESET)\n"; \
	fi

## lint-shell: Analyze shell script syntax and standards with shellcheck
lint-shell:
	@printf "$(BLUE)$(BOLD)▶ Checking shell scripts with shellcheck...$(RESET)\n"
	@FILES=$$(find $(SCRIPTS_DIR) -maxdepth 2 -name "*.sh" 2>/dev/null); \
	if [ -z "$$FILES" ]; then \
		printf "$(YELLOW)⚠ No shell scripts found in $(SCRIPTS_DIR)$(RESET)\n"; \
	elif command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $$FILES; \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_SHELLCHECK) \
			$$FILES; \
	else \
		for f in $$FILES; do bash -n "$$f"; done; \
	fi

## lint-yaml: Lint YAML files (excluding helm templates) with yamllint
lint-yaml:
	@printf "$(BLUE)$(BOLD)▶ Linting YAML files with yamllint...$(RESET)\n"
	@CONFIG="{extends: default, ignore: templates/helm/app-chart/templates, rules: {line-length: disable, document-start: disable, truthy: disable}}"; \
	if command -v yamllint >/dev/null 2>&1; then \
		yamllint -d "$$CONFIG" .; \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_YAMLLINT) \
			-d "$$CONFIG" .; \
	else \
		printf "$(YELLOW)⚠ yamllint and docker not available.$(RESET)\n"; \
	fi

## lint-md: Check Markdown files with markdownlint
lint-md:
	@printf "$(BLUE)$(BOLD)▶ Linting Markdown files with markdownlint...$(RESET)\n"
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint --disable MD013 MD032 MD012 -- "**/*.md"; \
	elif command -v npx >/dev/null 2>&1; then \
		npx --yes markdownlint-cli --disable MD013 MD032 MD012 -- "**/*.md"; \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/work:ro" $(IMAGE_MARKDOWNLINT) \
			--disable MD013 MD032 MD012 "**/*.md"; \
	else \
		printf "$(YELLOW)⚠ markdownlint and docker not available.$(RESET)\n"; \
	fi

## lint-actions: Lint GitHub Actions workflows with actionlint
lint-actions:
	@printf "$(BLUE)$(BOLD)▶ Linting GitHub Actions workflows with actionlint...$(RESET)\n"
	@if command -v actionlint >/dev/null 2>&1; then \
		actionlint; \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace:ro" -w /workspace $(IMAGE_ACTIONLINT); \
	else \
		printf "$(YELLOW)⚠ actionlint and docker not available.$(RESET)\n"; \
	fi

# ==============================================================================
# Security & Operational Auditing Targets
# ==============================================================================

## scan-secrets: Scan git history and working tree for leaked credentials with gitleaks
scan-secrets:
	@printf "$(BLUE)$(BOLD)▶ Scanning repository for secrets...$(RESET)\n"
	@chmod +x $(SCRIPTS_DIR)/scan-secrets.sh
	@./$(SCRIPTS_DIR)/scan-secrets.sh .

## audit-image: Audit container image efficiency and layer bloat with dive (usage: make audit-image IMAGE=app:tag)
audit-image:
	@if [ -z "$${IMAGE:-}" ]; then \
		printf "$(RED)$(BOLD)ERROR: IMAGE parameter is required.$(RESET)\n"; \
		printf "Usage: make audit-image IMAGE=my-image:latest [MIN_EFFICIENCY=0.98] [MAX_WASTED=0.02]\n"; \
		exit 1; \
	fi
	@chmod +x $(SCRIPTS_DIR)/audit-image.sh
	@./$(SCRIPTS_DIR)/audit-image.sh "$${IMAGE}" "$${MIN_EFFICIENCY:-0.98}" "$${MAX_WASTED:-0.02}"

# ==============================================================================
# Formatting & Maintenance Targets
# ==============================================================================

## fmt-tf: Format Terraform / OpenTofu files in templates/terraform
fmt-tf:
	@printf "$(BLUE)$(BOLD)▶ Formatting Terraform files ($(TF_DIR))...$(RESET)\n"
	@if command -v terraform >/dev/null 2>&1; then \
		terraform fmt $(TF_DIR); \
	elif command -v tofu >/dev/null 2>&1; then \
		tofu fmt $(TF_DIR); \
	elif [ "$(HAS_DOCKER)" = "true" ]; then \
		docker run --rm -v "$(ROOT_DIR):/workspace" -w /workspace $(IMAGE_TERRAFORM) \
			fmt $(TF_DIR); \
	fi

## fmt: Apply automatic formatters across the codebase
fmt: fmt-tf
	@printf "$(GREEN)$(BOLD)✔ Formatting complete.$(RESET)\n"

# ==============================================================================
# Help Documentation
# ==============================================================================

## help: Display this help menu with target descriptions
help:
	@printf "\n"
	@printf "$(BOLD)$(BLUE)======================================================================$(RESET)\n"
	@printf "$(BOLD)$(BLUE)  DevOps Skill - Automation & Validation Suite                        $(RESET)\n"
	@printf "$(BOLD)$(BLUE)======================================================================$(RESET)\n"
	@printf "$(BOLD)Usage:$(RESET) make $(CYAN)<target>$(RESET) [VARIABLE=value]\n\n"
	@printf "$(BOLD)Available Targets:$(RESET)\n"
	@awk '/^[a-zA-Z0-9_-]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpDesc = substr(lastLine, RSTART + 3); \
			sub(/^[a-zA-Z0-9_-]+:[ ]*/, "", helpDesc); \
			printf "  $(CYAN)%-16s$(RESET) %s\n", helpCommand, helpDesc; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
	@printf "\n"
	@printf "$(BOLD)Variables:$(RESET)\n"
	@printf "  $(YELLOW)IMAGE$(RESET)             Target image for audit-image (e.g. make audit-image IMAGE=my-app:1.0)\n"
	@printf "  $(YELLOW)MIN_EFFICIENCY$(RESET)    Minimum dive efficiency ratio (default: 0.98)\n"
	@printf "  $(YELLOW)MAX_WASTED$(RESET)        Maximum allowed wasted space ratio (default: 0.02)\n"
	@printf "\n"
