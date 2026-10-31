# syntax=docker/dockerfile:1.7
# ==============================================================================
# Production Eclipse Temurin 21 Multi-Stage Dockerfile for Java / Spring Boot 3.x
# - Layered JAR extraction: isolates dependencies, loader, snapshots, and code
#   into discrete Docker layers ordered from lowest to highest change frequency
# - eclipse-temurin:21-jre-jammy runtime: minimal footprint, verified OpenJDK
# - Unprivileged non-root execution (appuser UID 10001, GID 10001)
# - Container-native JVM ergonomics with cgroups v2 auto-sizing and fail-fast OOM
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Builder - compile application and extract Spring Boot Layered JAR
# ------------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-jammy AS builder

WORKDIR /build

# Install Maven for builds where wrapper is not checked in
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    maven \
 && rm -rf /var/lib/apt/lists/*

# Cache dependency resolution layer
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 \
    mvn dependency:go-offline -B

# Copy source tree and compile fat jar
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 \
    mvn clean package -DskipTests -B && \
    mv target/*.jar app.jar

# Extract Layered JAR slices
# Spring Boot 3.3+ uses jarmode=tools; Spring Boot 3.0-3.2 uses jarmode=layertools
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination /build/extracted || \
    java -Djarmode=layertools -jar app.jar extract --destination /build/extracted

# ------------------------------------------------------------------------------
# Stage 2: Runtime - minimal hardened JRE
# ------------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

# Create unprivileged application user and group (appuser:appgroup UID/GID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser

# Copy Spring Boot layers in ascending order of modification frequency:
# 1. External dependencies (rarely change, maximized cache hit rate)
COPY --chown=appuser:appgroup --from=builder /build/extracted/dependencies/ ./
# 2. Spring Boot loader classes
COPY --chown=appuser:appgroup --from=builder /build/extracted/spring-boot-loader/ ./
# 3. Snapshot dependencies (internal multi-module artifacts)
COPY --chown=appuser:appgroup --from=builder /build/extracted/snapshot-dependencies/ ./
# 4. Application code, resources, and configurations (changes on every commit)
COPY --chown=appuser:appgroup --from=builder /build/extracted/application/ ./

# Enforce unprivileged user execution
# hadolint ignore=DL3066
USER appuser:appgroup

EXPOSE 8080

# Production JVM Ergonomics:
# - -XX:MaxRAMPercentage=75.0: Sets max heap to 75% of container memory limit (cgroups v2 aware)
# - -XX:InitialRAMPercentage=50.0: Allocates 50% on startup to eliminate dynamic resizing latency
# - -XX:+ExitOnOutOfMemoryError: Immediately terminates process on OOM so orchestrator restarts pod
# - -Djava.security.egd=file:/dev/./urandom: Fast non-blocking entropy source for TLS/crypto
# Note: For Spring Boot 3.2+, the launcher is org.springframework.boot.loader.launch.JarLauncher;
#       for Spring Boot 3.0-3.1, use org.springframework.boot.loader.JarLauncher
ENTRYPOINT ["java", \
            "-XX:MaxRAMPercentage=75.0", \
            "-XX:InitialRAMPercentage=50.0", \
            "-XX:+ExitOnOutOfMemoryError", \
            "-Djava.security.egd=file:/dev/./urandom", \
            "org.springframework.boot.loader.launch.JarLauncher"]
