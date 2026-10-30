#!/usr/bin/env bash
# ==============================================================================
# Git Repository Secret Leak Scanner
# Scans git commit history and working tree using Gitleaks.
# Redacts detected credentials in console output and exits 1 on detected leaks.
# ==============================================================================
set -euo pipefail

TARGET_DIR="${1:-.}"

echo "======================================================================"
echo " Starting Secret Leak Scan on: ${TARGET_DIR}"
echo "======================================================================"

if command -v gitleaks >/dev/null 2>&1; then
  echo "[INFO] Using installed gitleaks binary: $(command -v gitleaks)"
  gitleaks detect \
    --source="${TARGET_DIR}" \
    --verbose \
    --redact \
    --exit-code=1
elif command -v docker >/dev/null 2>&1; then
  echo "[INFO] gitleaks not found in PATH. Running via containerized zricethezav/gitleaks..."
  ABS_PATH="$(cd "${TARGET_DIR}" && pwd)"
  docker run --rm \
    -v "${ABS_PATH}:/repo:ro" \
    zricethezav/gitleaks:latest detect \
    --source=/repo \
    --verbose \
    --redact \
    --exit-code=1
else
  echo "[ERROR] Neither 'gitleaks' nor 'docker' is available on PATH to execute scan." >&2
  exit 1
fi

echo "======================================================================"
echo " [SUCCESS] No secrets or sensitive credentials detected."
echo "======================================================================"
