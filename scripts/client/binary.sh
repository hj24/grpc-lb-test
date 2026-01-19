#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Build configuration
GOOS="${GOOS:-linux}"
GOARCH="${GOARCH:-amd64}"
OUTPUT_DIR="${PROJECT_ROOT}/client/bin"
OUTPUT_NAME="grpc-client"

cd "${PROJECT_ROOT}"

echo "==> Building client binary..."
echo "    GOOS:   ${GOOS}"
echo "    GOARCH: ${GOARCH}"
echo "    Output: ${OUTPUT_DIR}/${OUTPUT_NAME}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Build
CGO_ENABLED=0 GOOS="${GOOS}" GOARCH="${GOARCH}" \
  go build -ldflags="-s -w" -o "${OUTPUT_DIR}/${OUTPUT_NAME}" ./client

echo "==> Build complete: ${OUTPUT_DIR}/${OUTPUT_NAME}"
ls -lh "${OUTPUT_DIR}/${OUTPUT_NAME}"

