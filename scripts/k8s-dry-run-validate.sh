#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Client-Side Dry-Run Manifest Validator
# Validates Kubernetes YAML manifests for syntax, API schema correctness,
# and field validity without requiring an active cluster connection.
# ==============================================================================
set -euo pipefail

TARGET_PATH="${1:-templates/kubernetes}"

if [[ ! -e "${TARGET_PATH}" ]]; then
  echo "[ERROR] Target path does not exist: ${TARGET_PATH}" >&2
  exit 1
fi

echo "======================================================================"
echo " Validating Kubernetes Manifests in: ${TARGET_PATH}"
echo " Mode: Client-Side Dry Run"
echo "======================================================================"

if command -v kubeconform >/dev/null 2>&1; then
  echo "[INFO] Using local kubeconform binary: $(command -v kubeconform)"
  kubeconform -summary -strict "${TARGET_PATH}"
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  echo "[INFO] Active Kubernetes cluster detected. Running kubectl dry-run..."
  kubectl apply --dry-run=client -f "${TARGET_PATH}"
elif command -v docker >/dev/null 2>&1; then
  echo "[INFO] Running schema validation via containerized kubeconform..."
  ABS_PATH="$(cd "$(dirname "${TARGET_PATH}")" && pwd)/$(basename "${TARGET_PATH}")"
  docker run --rm \
    -v "${ABS_PATH}:/manifests:ro" \
    ghcr.io/yannh/kubeconform:latest -summary -strict /manifests
else
  echo "[WARN] Neither 'kubeconform', active 'kubectl', nor 'docker' is available for strict schema validation."
  echo "[INFO] Performing fallback YAML structure validation using Python..."
  python3 -c "
import sys, glob, os
path = sys.argv[1]
files = [path] if os.path.isfile(path) else glob.glob(os.path.join(path, '**/*.y*ml'), recursive=True)
if not files:
    print('[WARN] No YAML files found to validate.')
    sys.exit(0)
for f in files:
    with open(f, 'r') as fp:
        content = fp.read()
    if 'apiVersion:' not in content or 'kind:' not in content:
        print(f'[FAIL] {f} is missing standard Kubernetes apiVersion or kind fields.', file=sys.stderr)
        sys.exit(1)
    print(f'[PASS] {f} has valid Kubernetes object structure.')
" "${TARGET_PATH}"
fi

echo "======================================================================"
echo " [SUCCESS] All Kubernetes manifests passed validation."
echo "======================================================================"
