#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "==> Checking protoc installation..."

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed"
    echo "Please install protoc from https://github.com/protocolbuffers/protobuf/releases"
    exit 1
fi

echo "==> Checking protoc-gen-go..."
if ! command -v protoc-gen-go &> /dev/null; then
    echo "Installing protoc-gen-go..."
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
fi

echo "==> Checking protoc-gen-go-grpc..."
if ! command -v protoc-gen-go-grpc &> /dev/null; then
    echo "Installing protoc-gen-go-grpc..."
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
fi

cd "${PROJECT_ROOT}"

# Create protogen directory if it doesn't exist
mkdir -p protogen/echo

echo "==> Generating protobuf code..."
protoc \
  --go_out=. \
  --go_opt=module=github.com/hj24/grpc-lb-test \
  --go-grpc_out=. \
  --go-grpc_opt=module=github.com/hj24/grpc-lb-test \
  --proto_path=proto \
  proto/echo.proto

echo "==> Proto generation complete!"
echo "Generated files in: protogen/echo/"

