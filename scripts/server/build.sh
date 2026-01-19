#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-grpc-lb-test-server}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "==> Building server Docker image: ${FULL_IMAGE}"

cd "${PROJECT_ROOT}"

# Build Docker image (binary is built inside the container)
echo "==> Building Docker image with multi-stage build..."
docker build -t "${FULL_IMAGE}" -f server/Dockerfile .

echo "==> Server image built: ${FULL_IMAGE}"
docker images "${IMAGE_NAME}"
