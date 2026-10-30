# syntax=docker/dockerfile:1.7
# ==============================================================================
# Production Distroless Multi-Stage Dockerfile for Go
# - Zero package managers, zero shell, minimal CVE footprint
# - Rootless user execution (UID 65532 nonroot)
# - BuildKit compiler & module cache mounts for sub-second rebuilds
# - Bit-for-bit reproducible binary with -trimpath and stripped symbols
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build stage with compiler and toolchain
# ------------------------------------------------------------------------------
FROM golang:1.24-bookworm AS builder

WORKDIR /src

# Leverage cache mount for dependencies before copying full application code
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download -x

# Copy source tree
COPY . .

# Build statically linked binary with stripped symbols (-s -w) and trimmed paths
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /bin/server ./cmd/server

# ------------------------------------------------------------------------------
# Stage 2: Runtime stage on minimal distroless image
# ------------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# Copy binary from builder stage preserving nonroot ownership directly
COPY --chown=nonroot:nonroot --from=builder /bin/server /app/server

# Run as nonroot user (UID 65532, GID 65532)
USER nonroot:nonroot

# Expose application port
EXPOSE 8080

# Run compiled binary directly (no shell wrap)
ENTRYPOINT ["/app/server"]
