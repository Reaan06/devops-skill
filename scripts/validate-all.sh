#!/usr/bin/env bash
# ==============================================================================
# Unified DevOps & DevSecOps Validation Suite
# Validates containers, Kubernetes, Helm, Terraform, YAML, Markdown, Shell,
# and secret scanning across devops-skill templates and configurations.
# Supports native local CLI binaries with transparent Docker container fallback.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ------------------------------------------------------------------------------
# Terminal Color Setup (disabled if NO_COLOR is set or stdout is not a TTY)
# ------------------------------------------------------------------------------
if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
  if [[ -z "${NO_COLOR:-}" ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_GREEN="\033[0;32m"
    C_RED="\033[0;31m"
    C_YELLOW="\033[0;33m"
    C_BLUE="\033[0;34m"
    C_CYAN="\033[0;36m"
  else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
  fi
else
  C_RESET=""
  C_BOLD=""
  C_GREEN=""
  C_RED=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

TAG_PASS="${C_GREEN}[PASS]${C_RESET}"
TAG_FAIL="${C_RED}[FAIL]${C_RESET}"
TAG_SKIP="${C_YELLOW}[SKIP]${C_RESET}"
TAG_INFO="${C_CYAN}[INFO]${C_RESET}"

# ------------------------------------------------------------------------------
# Metric Counters
# ------------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
SKIPPED_CHECKS=0
FAILED_NAMES=()
SKIPPED_NAMES=()

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
log_header() {
  local title="$1"
  echo ""
  echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
  echo -e "${C_BOLD}${C_BLUE}▶ ${title}${C_RESET}"
  echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
}

record_pass() {
  local name="$1"
  echo -e "${TAG_PASS} ${name}"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

record_fail() {
  local name="$1"
  local reason="${2:-}"
  echo -e "${TAG_FAIL} ${name}"
  if [[ -n "${reason}" ]]; then
    echo -e "       ${C_RED}Reason: ${reason}${C_RESET}"
  fi
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_NAMES+=("${name}")
}

record_skip() {
  local name="$1"
  local reason="${2:-Tool unavailable}"
  echo -e "${TAG_SKIP} ${name} (${reason})"
  SKIPPED_CHECKS=$((SKIPPED_CHECKS + 1))
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  SKIPPED_NAMES+=("${name}")
}

# Detect Docker capability
HAS_DOCKER=false
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  HAS_DOCKER=true
fi

echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}  DevOps Skill - Unified Validation Suite (Cascading Check)            ${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}  Repository: ${REPO_ROOT}${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}  Docker Fallback: ${HAS_DOCKER}${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"

# ==============================================================================
# 1. YAML Syntax Validation (yamllint or python fallback)
# ==============================================================================
log_header "1/8 YAML Syntax Validation"
YAMLLINT_CONFIG="{extends: default, ignore: templates/helm/app-chart/templates, rules: {line-length: disable, document-start: disable, truthy: disable}}"

if command -v yamllint >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local yamllint binary: $(command -v yamllint)"
  if yamllint -d "${YAMLLINT_CONFIG}" .; then
    record_pass "YAML Syntax (yamllint)"
  else
    record_fail "YAML Syntax (yamllint)" "Syntax or formatting errors detected by yamllint"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} yamllint not in PATH; running via container cytopia/yamllint:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace cytopia/yamllint:latest -d "${YAMLLINT_CONFIG}" .; then
    record_pass "YAML Syntax (docker:cytopia/yamllint)"
  else
    record_fail "YAML Syntax (docker:cytopia/yamllint)" "Syntax or formatting errors detected by yamllint"
  fi
elif command -v python3 >/dev/null 2>&1; then
  echo -e "${TAG_INFO} yamllint not found; running Python YAML validation fallback"
  if python3 -c "
import glob, sys
files = [f for f in glob.glob('**/*.y*ml', recursive=True) if 'templates/helm/' not in f]
if not files:
    sys.exit(0)
try:
    import yaml
    for f in files:
        with open(f, 'r', encoding='utf-8') as fp:
            list(yaml.safe_load_all(fp))
except ImportError:
    for f in files:
        with open(f, 'r', encoding='utf-8') as fp:
            for i, line in enumerate(fp, 1):
                if '\t' in line:
                    sys.stderr.write(f'{f}:{i}: Tab character detected in YAML file\n')
                    sys.exit(1)
"; then
    record_pass "YAML Syntax (python fallback)"
  else
    record_fail "YAML Syntax (python fallback)" "Python YAML check detected syntax errors"
  fi
else
  record_skip "YAML Syntax" "Neither yamllint, docker, nor python3 available"
fi

# ==============================================================================
# 2. Markdown Formatting Validation (markdownlint or syntax check)
# ==============================================================================
log_header "2/8 Markdown Formatting Validation"
if command -v markdownlint >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local markdownlint binary: $(command -v markdownlint)"
  if markdownlint --disable MD013 MD032 MD012 -- "**/*.md"; then
    record_pass "Markdown Formatting (markdownlint)"
  else
    record_fail "Markdown Formatting (markdownlint)" "Markdownlint violations detected"
  fi
elif command -v npx >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Running markdownlint via npx markdownlint-cli"
  if npx --yes markdownlint-cli --disable MD013 MD032 MD012 -- "**/*.md"; then
    record_pass "Markdown Formatting (npx:markdownlint-cli)"
  else
    record_fail "Markdown Formatting (npx:markdownlint-cli)" "Markdownlint violations detected"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} Running markdownlint via container tmknom/markdownlint:latest"
  if docker run --rm -v "${REPO_ROOT}:/work:ro" tmknom/markdownlint:latest --disable MD013 MD032 MD012 "**/*.md"; then
    record_pass "Markdown Formatting (docker:tmknom/markdownlint)"
  else
    record_fail "Markdown Formatting (docker:tmknom/markdownlint)" "Markdownlint violations detected"
  fi
else
  echo -e "${TAG_INFO} Checking markdown file readability and non-empty structure"
  MD_FAIL=0
  while IFS= read -r -d '' md_file; do
    if [[ ! -s "${md_file}" ]]; then
      echo -e "${TAG_FAIL} Empty markdown file: ${md_file}"
      MD_FAIL=1
    fi
  done < <(find . -name "*.md" -not -path "*/.*" -print0)
  if [[ "${MD_FAIL}" -eq 0 ]]; then
    record_pass "Markdown Formatting (syntax check fallback)"
  else
    record_fail "Markdown Formatting (syntax check fallback)" "Empty or unreadable markdown files found"
  fi
fi

# ==============================================================================
# 3. Shell Scripts Syntax & Best Practices (shellcheck or bash -n)
# ==============================================================================
log_header "3/8 Shell Scripts Syntax & Best Practices"
SHELL_FILES=()
while IFS= read -r -d '' sh_file; do
  # Avoid checking temporary or hidden files
  SHELL_FILES+=("${sh_file#./}")
done < <(find scripts -maxdepth 2 -name "*.sh" -print0 2>/dev/null || true)

if [[ ${#SHELL_FILES[@]} -eq 0 ]]; then
  record_skip "Shell Scripts" "No .sh files found in scripts/"
elif command -v shellcheck >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local shellcheck binary: $(command -v shellcheck)"
  if shellcheck "${SHELL_FILES[@]}"; then
    record_pass "Shell Scripts (shellcheck)"
  else
    record_fail "Shell Scripts (shellcheck)" "ShellCheck warnings or errors detected"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} shellcheck not in PATH; running via container koalaman/shellcheck:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace koalaman/shellcheck:latest "${SHELL_FILES[@]}"; then
    record_pass "Shell Scripts (docker:koalaman/shellcheck)"
  else
    record_fail "Shell Scripts (docker:koalaman/shellcheck)" "ShellCheck violations detected"
  fi
else
  echo -e "${TAG_INFO} Running bash -n syntax verification fallback"
  BASH_FAIL=0
  for sh_f in "${SHELL_FILES[@]}"; do
    if ! bash -n "${sh_f}"; then
      BASH_FAIL=1
    fi
  done
  if [[ "${BASH_FAIL}" -eq 0 ]]; then
    record_pass "Shell Scripts (bash -n syntax check)"
  else
    record_fail "Shell Scripts (bash -n)" "Shell syntax errors detected"
  fi
fi

# ==============================================================================
# 4. Dockerfiles Best Practices (hadolint)
# ==============================================================================
log_header "4/8 Dockerfiles Best Practices (hadolint)"
DOCKER_FILES=()
while IFS= read -r -d '' df; do
  DOCKER_FILES+=("${df#./}")
done < <(find templates/containers -name "Dockerfile*" -print0 2>/dev/null || true)

if [[ ${#DOCKER_FILES[@]} -eq 0 ]]; then
  record_skip "Dockerfiles" "No Dockerfiles found in templates/containers"
elif command -v hadolint >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local hadolint binary: $(command -v hadolint)"
  if hadolint --ignore DL3008 --ignore DL3013 --ignore DL3066 "${DOCKER_FILES[@]}"; then
    record_pass "Dockerfiles (hadolint)"
  else
    record_fail "Dockerfiles (hadolint)" "Hadolint issues detected in templates/containers"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} hadolint not in PATH; running via container hadolint/hadolint:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace hadolint/hadolint:latest /bin/hadolint --ignore DL3008 --ignore DL3013 --ignore DL3066 "${DOCKER_FILES[@]}"; then
    record_pass "Dockerfiles (docker:hadolint/hadolint)"
  else
    record_fail "Dockerfiles (docker:hadolint/hadolint)" "Hadolint issues detected in templates/containers"
  fi
else
  record_skip "Dockerfiles (hadolint)" "Neither hadolint nor docker available"
fi

# ==============================================================================
# 5. Kubernetes Manifests & CRDs (kubeconform or k8s-dry-run-validate.sh)
# ==============================================================================
log_header "5/8 Kubernetes Manifests & CRDs Validation"
K8S_TARGETS=()
[[ -d "templates/kubernetes" ]] && K8S_TARGETS+=("templates/kubernetes")
[[ -d "templates/kustomize/base" ]] && K8S_TARGETS+=("templates/kustomize/base")

if [[ ${#K8S_TARGETS[@]} -eq 0 ]]; then
  record_skip "Kubernetes Manifests" "No manifests found in templates/kubernetes or templates/kustomize/base"
elif command -v kubeconform >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local kubeconform binary: $(command -v kubeconform)"
  if kubeconform -summary -strict -ignore-missing-schemas "${K8S_TARGETS[@]}"; then
    record_pass "Kubernetes Manifests (kubeconform)"
  else
    record_fail "Kubernetes Manifests (kubeconform)" "Schema validation errors in manifests"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} kubeconform not in PATH; running via container ghcr.io/yannh/kubeconform:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace ghcr.io/yannh/kubeconform:latest -summary -strict -ignore-missing-schemas "${K8S_TARGETS[@]}"; then
    record_pass "Kubernetes Manifests (docker:ghcr.io/yannh/kubeconform)"
  else
    record_fail "Kubernetes Manifests (docker:ghcr.io/yannh/kubeconform)" "Schema validation errors in manifests"
  fi
elif [[ -x "${REPO_ROOT}/scripts/k8s-dry-run-validate.sh" ]]; then
  echo -e "${TAG_INFO} Running scripts/k8s-dry-run-validate.sh fallback"
  if "${REPO_ROOT}/scripts/k8s-dry-run-validate.sh" templates/kubernetes; then
    record_pass "Kubernetes Manifests (k8s-dry-run-validate.sh)"
  else
    record_fail "Kubernetes Manifests (k8s-dry-run-validate.sh)" "Dry-run validation failed"
  fi
else
  record_skip "Kubernetes Manifests" "Neither kubeconform, docker, nor k8s-dry-run-validate.sh available"
fi

# ==============================================================================
# 6. Helm Charts Validation (helm lint)
# ==============================================================================
log_header "6/8 Helm Charts Validation"
HELM_CHART="templates/helm/app-chart"

if [[ ! -d "${HELM_CHART}" ]]; then
  record_skip "Helm Charts" "Directory ${HELM_CHART} does not exist"
elif command -v helm >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local helm binary: $(command -v helm)"
  if helm lint "${HELM_CHART}"; then
    record_pass "Helm Chart (helm lint)"
  else
    record_fail "Helm Chart (helm lint)" "Linting errors in ${HELM_CHART}"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} helm not in PATH; running via container alpine/helm:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace alpine/helm:latest lint "${HELM_CHART}"; then
    record_pass "Helm Chart (docker:alpine/helm)"
  else
    record_fail "Helm Chart (docker:alpine/helm)" "Linting errors in ${HELM_CHART}"
  fi
else
  record_skip "Helm Charts" "Neither helm nor docker available"
fi

# ==============================================================================
# 7. Terraform Formatting & Syntax (terraform fmt -check -diff)
# ==============================================================================
log_header "7/8 Terraform Formatting & Syntax Validation"
TF_DIR="templates/terraform"

if [[ ! -d "${TF_DIR}" ]]; then
  record_skip "Terraform" "Directory ${TF_DIR} does not exist"
elif command -v terraform >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local terraform binary: $(command -v terraform)"
  if terraform fmt -check -diff "${TF_DIR}"; then
    record_pass "Terraform Format & Syntax (terraform)"
  else
    record_fail "Terraform Format & Syntax (terraform)" "Formatting differences detected in ${TF_DIR}"
  fi
elif command -v tofu >/dev/null 2>&1; then
  echo -e "${TAG_INFO} Using local tofu binary: $(command -v tofu)"
  if tofu fmt -check -diff "${TF_DIR}"; then
    record_pass "Terraform Format & Syntax (tofu)"
  else
    record_fail "Terraform Format & Syntax (tofu)" "Formatting differences detected in ${TF_DIR}"
  fi
elif [[ "${HAS_DOCKER}" == "true" ]]; then
  echo -e "${TAG_INFO} terraform/tofu not in PATH; running via container hashicorp/terraform:latest"
  if docker run --rm -v "${REPO_ROOT}:/workspace:ro" -w /workspace hashicorp/terraform:latest fmt -check -diff "${TF_DIR}"; then
    record_pass "Terraform Format & Syntax (docker:hashicorp/terraform)"
  else
    record_fail "Terraform Format & Syntax (docker:hashicorp/terraform)" "Formatting differences detected in ${TF_DIR}"
  fi
else
  record_skip "Terraform Format & Syntax" "Neither terraform, tofu, nor docker available"
fi

# ==============================================================================
# 8. Secret Leak Detection (scripts/scan-secrets.sh)
# ==============================================================================
log_header "8/8 Secret Detection (Gitleaks)"
if [[ -x "${REPO_ROOT}/scripts/scan-secrets.sh" ]]; then
  if "${REPO_ROOT}/scripts/scan-secrets.sh" "${REPO_ROOT}"; then
    record_pass "Secret Detection (scripts/scan-secrets.sh)"
  else
    record_fail "Secret Detection (scripts/scan-secrets.sh)" "Secret leaks or sensitive credentials detected"
  fi
else
  record_skip "Secret Detection" "scripts/scan-secrets.sh not found or not executable"
fi

# ==============================================================================
# Summary Report and Exit Code
# ==============================================================================
echo ""
echo -e "${C_BOLD}======================================================================${C_RESET}"
echo -e "${C_BOLD}                    VALIDATION SUMMARY REPORT                         ${C_RESET}"
echo -e "${C_BOLD}======================================================================${C_RESET}"
echo -e " Total Checks:   ${C_BOLD}${TOTAL_CHECKS}${C_RESET}"
echo -e " Passed Checks:  ${C_GREEN}${PASSED_CHECKS}${C_RESET}"
echo -e " Failed Checks:  ${C_RED}${FAILED_CHECKS}${C_RESET}"
echo -e " Skipped Checks: ${C_YELLOW}${SKIPPED_CHECKS}${C_RESET}"
echo -e "----------------------------------------------------------------------"

if [[ "${FAILED_CHECKS}" -gt 0 ]]; then
  echo -e "${C_BOLD}${C_RED}❌ FAILED CHECKS (${FAILED_CHECKS}):${C_RESET}"
  for f_name in "${FAILED_NAMES[@]}"; do
    echo -e "  - ${C_RED}${f_name}${C_RESET}"
  done
  echo -e "----------------------------------------------------------------------"
  echo -e "${C_BOLD}${C_RED}[OVERALL STATUS] FAILED - Please address the issues listed above.${C_RESET}"
  exit 1
else
  echo -e "${C_BOLD}${C_GREEN}[OVERALL STATUS] PASSED - All devops-skill checks succeeded!${C_RESET}"
  exit 0
fi
