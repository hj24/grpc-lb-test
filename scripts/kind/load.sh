#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Image names
SERVER_IMAGE="${SERVER_IMAGE:-grpc-lb-test-server:latest}"
CLIENT_IMAGE="${CLIENT_IMAGE:-grpc-lb-test-client:latest}"

# Kind cluster name
KIND_CLUSTER="${KIND_CLUSTER:-kind}"

echo "==> Loading images to kind cluster: ${KIND_CLUSTER}"

# Check if kind cluster exists
if ! kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
    echo "Error: kind cluster '${KIND_CLUSTER}' not found"
    echo "Available clusters:"
    kind get clusters
    exit 1
fi

# Load server image
echo "==> Loading server image: ${SERVER_IMAGE}"
kind load docker-image "${SERVER_IMAGE}" --name "${KIND_CLUSTER}"

# Load client image
echo "==> Loading client image: ${CLIENT_IMAGE}"
kind load docker-image "${CLIENT_IMAGE}" --name "${KIND_CLUSTER}"

echo "==> Images loaded successfully!"
echo "    - ${SERVER_IMAGE}"
echo "    - ${CLIENT_IMAGE}"

