#!/bin/bash
set -euo pipefail

#
# docker-build.sh — Build the travel router image using Docker
#
# Prerequisites:
#   1. Docker installed and running
#   2. config.env filled out
#   3. ./configure.sh already run
#
# Usage:
#   ./docker-build.sh              # Build image
#   ./docker-build.sh --no-cache   # Rebuild from scratch
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="rpi-travel-router-builder"

# Check prerequisites
if [[ ! -f "${SCRIPT_DIR}/openwrt/files/etc/config/passwall" ]]; then
    echo "ERROR: Run ./configure.sh first!"
    exit 1
fi

# Parse args
DOCKER_BUILD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-cache) DOCKER_BUILD_ARGS+=("--no-cache") ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

echo "=== Building Docker image (this downloads OpenWrt ImageBuilder, ~1GB) ==="
docker build \
    --platform linux/amd64 \
    "${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"}" \
    -t "${IMAGE_NAME}" \
    "${SCRIPT_DIR}"

echo ""
echo "=== Running image build ==="
mkdir -p "${SCRIPT_DIR}/output"
docker run --rm \
    --platform linux/amd64 \
    -v "${SCRIPT_DIR}/output":/output \
    "${IMAGE_NAME}"

echo ""
echo "=== Done! ==="
echo "Output images:"
ls -lh "${SCRIPT_DIR}/output/"*.img.gz 2>/dev/null || echo "  (no images found — check build output above)"
echo ""
echo "Flash to SD card:"
echo "  gunzip -k output/*.img.gz"
echo "  sudo dd if=output/*.img of=/dev/sdX bs=4M status=progress"
