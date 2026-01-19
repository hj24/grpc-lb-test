FROM golang:1.24-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY proto/ ./proto/
COPY protogen/ ./protogen/
COPY server/ ./server/

# Build binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o grpc-server ./server

# Final stage
FROM alpine:latest

# Add ca-certificates for HTTPS connections
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/grpc-server /app/grpc-server

# Expose gRPC port
EXPOSE 9000

# Run the binary
ENTRYPOINT ["/app/grpc-server"]
