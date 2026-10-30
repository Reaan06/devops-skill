#!/usr/bin/env bash
# ==============================================================================
# Container Image Efficiency & Layer Bloat Auditor
# Analyzes candidate Docker images using dive.
# Enforces minimum efficiency score (default: 98%) and wasted space ceilings.
# ==============================================================================
set -euo pipefail

IMAGE_TAG="${1:-}"
MIN_EFFICIENCY="${2:-0.98}"
MAX_WASTED_RATIO="${3:-0.02}"

if [[ -z "${IMAGE_TAG}" ]]; then
  echo "Usage: $0 <image-name:tag> [min-efficiency (e.g. 0.98)] [max-wasted-ratio (e.g. 0.02)]"
  echo "Example: $0 my-app:latest 0.98 0.02"
  exit 1
fi

echo "======================================================================"
echo " Starting Container Image Audit: ${IMAGE_TAG}"
echo " Minimum Efficiency Target: ${MIN_EFFICIENCY}"
echo " Maximum Wasted Ratio:     ${MAX_WASTED_RATIO}"
echo "======================================================================"

# Resolve dive executable
DIVE_BIN=""
if command -v dive >/dev/null 2>&1; then
  DIVE_BIN="$(command -v dive)"
elif [[ -x "${HOME}/.local/bin/dive" ]]; then
  DIVE_BIN="${HOME}/.local/bin/dive"
fi

if [[ -n "${DIVE_BIN}" ]]; then
  echo "[INFO] Using local dive binary: ${DIVE_BIN}"
  CI=true "${DIVE_BIN}" "${IMAGE_TAG}" \
    --ci \
    --highestUserWastedPercent="${MAX_WASTED_RATIO}" \
    --lowestEfficiency="${MIN_EFFICIENCY}"
elif command -v docker >/dev/null 2>&1; then
  echo "[INFO] dive not found locally. Running via containerized wagoodman/dive..."
  docker run --rm \
    -e CI=true \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    wagoodman/dive:latest "${IMAGE_TAG}" \
    --ci \
    --highestUserWastedPercent="${MAX_WASTED_RATIO}" \
    --lowestEfficiency="${MIN_EFFICIENCY}"
else
  echo "[ERROR] Neither 'dive' nor 'docker' is available on PATH to execute audit." >&2
  exit 1
fi

echo "======================================================================"
echo " [SUCCESS] Image ${IMAGE_TAG} satisfies efficiency and layer constraints."
echo "======================================================================"
