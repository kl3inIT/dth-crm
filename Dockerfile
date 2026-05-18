# syntax=docker/dockerfile:1.7

# =========================================================================
# Stage 1 — build: bootJar with Vaadin production mode.
# Gradle/Vaadin caches live in --mount=type=cache (BuildKit), so subsequent
# rebuilds skip dependency download + node_modules install.
# =========================================================================
FROM eclipse-temurin:21.0.3_9-jdk AS builder
WORKDIR /workspace

# Copy build descriptors first so the cache mount layer doesn't bust on source edits
COPY gradlew settings.gradle build.gradle gradle.properties ./
COPY gradle ./gradle
RUN chmod +x gradlew

COPY . .
RUN --mount=type=cache,target=/root/.gradle \
    --mount=type=cache,target=/workspace/.gradle \
    --mount=type=cache,target=/workspace/node_modules \
    ./gradlew --no-daemon bootJar -Pvaadin.productionMode -x test

# =========================================================================
# Stage 2 — runtime: JRE-only image, non-root user, healthcheck.
# Includes fonts (Jmix reports need them for PDF/XLSX) and curl for the probe.
# =========================================================================
FROM eclipse-temurin:21.0.3_9-jre-jammy AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        libfreetype6 \
        fonts-dejavu \
        fontconfig \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 dthcrm \
    && useradd  --system --uid 1001 --gid dthcrm --home-dir /app --shell /sbin/nologin dthcrm \
    && mkdir -p /app/heapdumps /app/.jmix /app/file-storage \
    && chown -R dthcrm:dthcrm /app

WORKDIR /app
COPY --from=builder --chown=dthcrm:dthcrm /workspace/build/libs/dth-crm.jar /app/app.jar

ENV JAVA_TOOL_OPTIONS="-Xmx2g -Xms512m -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/app/heapdumps -XX:MaxRAMPercentage=75"
ENV DTH_SERVER_PORT=8080

USER dthcrm
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl -fsS http://localhost:8080/ > /dev/null || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
