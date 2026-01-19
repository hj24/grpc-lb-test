.PHONY: help proto server-binary client-binary server-image client-image kind-load deploy-server deploy-client deploy undeploy clean all

# Colors for output
CYAN := \033[36m
RESET := \033[0m

help: ## Show this help message
	@echo "$(CYAN)Available targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'

proto: ## Generate protobuf code from .proto files
	@echo "$(CYAN)==> Generating protobuf code...$(RESET)"
	@./scripts/proto/protoc.sh

server-binary: ## Build server binary for linux/amd64 (for local testing)
	@echo "$(CYAN)==> Building server binary...$(RESET)"
	@./scripts/server/binary.sh

client-binary: ## Build client binary for linux/amd64 (for local testing)
	@echo "$(CYAN)==> Building client binary...$(RESET)"
	@./scripts/client/binary.sh

binaries: server-binary client-binary ## Build both server and client binaries (for local testing)

server-image: ## Build server Docker image (compiles inside container)
	@echo "$(CYAN)==> Building server Docker image...$(RESET)"
	@./scripts/server/build.sh

client-image: ## Build client Docker image (compiles inside container)
	@echo "$(CYAN)==> Building client Docker image...$(RESET)"
	@./scripts/client/build.sh

images: server-image client-image ## Build both server and client Docker images

kind-load: images ## Load Docker images into kind cluster
	@echo "$(CYAN)==> Loading images to kind...$(RESET)"
	@./scripts/kind/load.sh

deploy-namespace: ## Create test namespace if it doesn't exist
	@echo "$(CYAN)==> Creating namespace 'test'...$(RESET)"
	@kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f -

deploy-server: deploy-namespace ## Deploy gRPC server to Kubernetes
	@echo "$(CYAN)==> Deploying gRPC server...$(RESET)"
	@kubectl apply -f deploy/server/service.yaml
	@kubectl apply -f deploy/server/deployment.yaml
	@echo "$(CYAN)==> Waiting for server pods to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l app=grpc-server -n test --timeout=60s || true

deploy-client: deploy-namespace ## Deploy gRPC client to Kubernetes
	@echo "$(CYAN)==> Deploying gRPC client...$(RESET)"
	@kubectl apply -f deploy/client/deployment.yaml

deploy: deploy-server deploy-client ## Deploy both server and client to Kubernetes

undeploy: ## Remove all deployments from Kubernetes
	@echo "$(CYAN)==> Removing deployments...$(RESET)"
	@kubectl delete -f deploy/client/deployment.yaml --ignore-not-found=true
	@kubectl delete -f deploy/server/deployment.yaml --ignore-not-found=true
	@kubectl delete -f deploy/server/service.yaml --ignore-not-found=true

logs-server: ## Show server logs
	@kubectl logs -n test -l app=grpc-server --tail=100 -f

logs-client: ## Show client logs
	@kubectl logs -n test -l app=grpc-client --tail=100 -f

status: ## Show deployment status
	@echo "$(CYAN)==> Server status:$(RESET)"
	@kubectl get pods,svc -n test -l app=grpc-server
	@echo ""
	@echo "$(CYAN)==> Client status:$(RESET)"
	@kubectl get pods -n test -l app=grpc-client

clean: ## Clean build artifacts
	@echo "$(CYAN)==> Cleaning build artifacts...$(RESET)"
	@rm -rf server/bin client/bin
	@rm -rf protogen/echo/*.pb.go
	@echo "$(CYAN)==> Clean complete$(RESET)"

all: proto images kind-load deploy ## Full build and deploy pipeline
	@echo "$(CYAN)==> All done! Run 'make logs-client' to see load test results$(RESET)"

# Development targets
run-server: proto ## Run server locally
	@echo "$(CYAN)==> Running server locally on :9000...$(RESET)"
	@go run ./server

run-client: proto ## Run client locally (requires server running)
	@echo "$(CYAN)==> Running client locally...$(RESET)"
	@go run ./client -target localhost:9000 -total 100 -concurrency 10 -conns 3

test-local: ## Quick local test (run server in background, then client)
	@echo "$(CYAN)==> Starting server...$(RESET)"
	@go run ./server &
	@sleep 2
	@echo "$(CYAN)==> Running client...$(RESET)"
	@go run ./client -target localhost:9000 -total 100 -concurrency 10 -conns 3
	@killall grpc-server || true
