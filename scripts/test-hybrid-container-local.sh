#!/usr/bin/env bash
# Build and exercise the hybrid package-source canary on the local host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${AZL_HYBRID_CANARY_WORKDIR:-$HOME/azl-work/hybrid-container-canary}"
IMAGE_REF="${AZL_HYBRID_CANARY_IMAGE:-localhost/azurelinux-desktop-hybrid:canary}"
LOG_DIR="$WORKDIR/logs"

mkdir -p "$WORKDIR"
podman unshare rm -rf "$LOG_DIR" 2>/dev/null || rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

AZL_CONTAINER_WORKDIR="$WORKDIR/build" \
    "$REPO_ROOT/scripts/build-hybrid-container.sh" "$IMAGE_REF"

podman run --rm --user root \
    -v "$REPO_ROOT/scripts/test-hybrid-container.sh:/usr/local/bin/test-hybrid-container:ro,Z" \
    -v "$LOG_DIR:/logs:Z" \
    "$IMAGE_REF" \
    /usr/local/bin/test-hybrid-container

echo "Canary logs: $LOG_DIR"
