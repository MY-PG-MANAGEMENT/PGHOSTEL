# syntax=docker/dockerfile:1.7
# =============================================================================
# PG Manager — Spring Boot 3.3 / Java 21 production image
#
# Build context is the REPOSITORY ROOT, not deployment/:
#     docker build -f deployment/Dockerfile -t pgmanager-api .
#
# Four stages, each with a single job:
#   1. deps      — resolve the Gradle dependency graph (cached independently of source)
#   2. builder   — compile and produce the executable jar
#   3. extractor — split the jar into Spring Boot layers (ordered by change frequency)
#   4. runtime   — JRE only, non-root, no build toolchain, no source
#
# Base images are multi-arch (linux/amd64 + linux/arm64/v8), so this builds and runs
# unchanged on whichever architecture the platform gives you. Deliberately NOT Alpine: musl's
# allocator and thread defaults have repeatedly caused latency outliers under G1 in
# JVM workloads, and the arm64 Alpine JRE tags lag the Ubuntu ones.
# =============================================================================


# -----------------------------------------------------------------------------
# Stage 1 — dependency resolution
#
# Only the build scripts are copied here. As long as build.gradle / settings.gradle
# are untouched, this whole layer is reused even when every .java file changed —
# which is the common case and the single biggest build-time saving.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-jammy AS deps

WORKDIR /workspace

# Wrapper first: it pins the Gradle distribution, and downloading that is its own
# expensive step worth caching separately from the dependency download.
COPY backend/gradlew                       ./gradlew
COPY backend/gradle/wrapper/               ./gradle/wrapper/
RUN chmod +x ./gradlew

# BuildKit cache mount: the Gradle home survives between builds without ever
# becoming part of an image layer. Requires DOCKER_BUILDKIT=1 (default in Docker 23+).
RUN --mount=type=cache,target=/root/.gradle,sharing=locked \
    ./gradlew --no-daemon --version

COPY backend/settings.gradle backend/build.gradle ./

# Warm the dependency cache. `|| true` is deliberate and is NOT hiding a build failure:
# this step exists solely to populate the cache, and any genuine resolution error will
# surface again — fatally — in the builder stage below.
RUN --mount=type=cache,target=/root/.gradle,sharing=locked \
    (./gradlew --no-daemon dependencies --configuration runtimeClasspath > /dev/null 2>&1 || true) \
 && (./gradlew --no-daemon dependencies --configuration compileClasspath > /dev/null 2>&1 || true)


# -----------------------------------------------------------------------------
# Stage 2 — compile
#
# Tests are NOT run here. CI runs them on the host runner (see .github/workflows),
# where they are faster, produce readable reports, and — importantly — can reach a
# Docker daemon for the Testcontainers integration tests. Running them inside the
# image build would need docker-in-docker for no benefit.
# -----------------------------------------------------------------------------
FROM deps AS builder

WORKDIR /workspace

COPY backend/src ./src

RUN --mount=type=cache,target=/root/.gradle,sharing=locked \
    ./gradlew --no-daemon clean bootJar -x test \
 && cp build/libs/*.jar /workspace/app.jar


# -----------------------------------------------------------------------------
# Stage 3 — layer extraction
#
# A fat jar copied as one COPY is a single ~60 MB layer that is re-pushed and
# re-pulled on every code change. Spring Boot's layered format splits it so the
# ~55 MB of third-party dependencies land in a layer that changes only when
# build.gradle does, and the ~2 MB of application classes are the only thing that
# actually moves on a normal deploy.
#
# NOTE: `layertools` is deprecated as of Spring Boot 3.3 in favour of
# `-Djarmode=tools extract --layers`. It still works on 3.3.5. When this project
# moves to Spring Boot 3.4+, switch the command below.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-jammy AS extractor

WORKDIR /extract
COPY --from=builder /workspace/app.jar ./app.jar
RUN java -Djarmode=layertools -jar app.jar extract


# -----------------------------------------------------------------------------
# Stage 4 — runtime
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-jammy AS runtime

# Build metadata. Passed by CI; surfaced by `docker inspect` so a running container
# can always be traced back to the exact commit that produced it.
ARG BUILD_VERSION=dev
ARG BUILD_COMMIT=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="pg-manager-backend" \
      org.opencontainers.image.description="PG Manager multi-tenant SaaS API" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${BUILD_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="Proprietary"

# curl is required by HEALTHCHECK; tzdata by -Duser.timezone. Both installed in one
# layer with the apt lists deleted in the same RUN, so the cache never persists.
# --no-install-recommends keeps this to a few hundred KB.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl tzdata \
 && rm -rf /var/lib/apt/lists/*

# Non-root, no login shell, no home directory to write into. A high fixed UID/GID
# (10001) avoids colliding with any host user if a volume is ever bind-mounted.
RUN groupadd --system --gid 10001 appgroup \
 && useradd  --system --uid 10001 --gid appgroup --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

# Writable directories. The container runs with a read-only root filesystem
# (the container filesystem is read-only where the platform allows it), so these are
# the only paths the JVM may write to and
# each is backed by a tmpfs or a named volume at runtime.
RUN mkdir -p /app/logs /app/tmp \
 && chown -R appuser:appgroup /app

# Layers copied most-stable-first so a code-only change invalidates just the last COPY.
COPY --from=extractor --chown=appuser:appgroup /extract/dependencies/          ./
COPY --from=extractor --chown=appuser:appgroup /extract/spring-boot-loader/    ./
COPY --from=extractor --chown=appuser:appgroup /extract/snapshot-dependencies/ ./
COPY --from=extractor --chown=appuser:appgroup /extract/application/           ./

USER appuser:appgroup

# --- JVM configuration -------------------------------------------------------
# Overridable per environment via JAVA_OPTS; never bake sizes into the image.
#
#   UseContainerSupport   — on by default since JDK 10, stated explicitly so nobody
#                           "helpfully" adds -Xmx and breaks cgroup awareness.
#   MaxRAMPercentage=70   — heap ceiling as a share of the *container* limit, not the
#                           host's 24 GB. The remaining 30% is not waste: it is
#                           metaspace, code cache, thread stacks, GC structures and
#                           direct buffers (Lettuce/Netty allocate off-heap). Setting
#                           this to 90 is the classic way to get OOM-killed by the
#                           kernel while the JVM still believes it has headroom.
#   ExitOnOutOfMemoryError— die instead of limping. The platform restarts a dead container;
#                           nothing rescues a JVM thrashing on a full heap.
#   HeapDumpOnOutOfMemory — dump to the mounted logs volume so the evidence outlives
#                           the container.
ENV JAVA_OPTS="\
-XX:+UseContainerSupport \
-XX:MaxRAMPercentage=70.0 \
-XX:InitialRAMPercentage=40.0 \
-XX:+UseG1GC \
-XX:MaxGCPauseMillis=200 \
-XX:+UseStringDeduplication \
-XX:+ExitOnOutOfMemoryError \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/app/logs \
-XX:+AlwaysActAsServerClassMachine \
-Djava.security.egd=file:/dev/urandom \
-Djava.awt.headless=true \
-Dfile.encoding=UTF-8 \
-Dsun.jnu.encoding=UTF-8 \
-Djava.io.tmpdir=/app/tmp"

ENV SPRING_PROFILES_ACTIVE=prod \
    SERVER_PORT=8080 \
    MANAGEMENT_PORT=9091 \
    TZ=Asia/Kolkata \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 8080 = API traffic. On Koyeb this is the port with the public HTTP route.
# 9091 = actuator. Deliberately a SEPARATE port: Spring Boot puts the management
#        endpoints in a child context, so neither the app's security filter chain nor
#        ApiLogFilter applies to it. Both halves of that matter:
#          * ApiLogFilter has no path exclusions, so probing /actuator/health on 8080
#            every 15s would write thousands of rows a day into api_request_log.
#          * SecurityConfig ends with anyRequest().authenticated(), so a health check
#            aimed at 8080 gets 401 and can NEVER pass — the deploy would hang and
#            roll back on what looks like an auth error.
#        Declare this port on the Koyeb service with NO route: everything it serves is
#        unauthenticated, so routing it would publish /actuator/metrics publicly.
EXPOSE 8080 9091

# Readiness, not liveness: `depends_on: condition: service_healthy` should mean
# "can serve requests", which includes a reachable database. See application-prod.yml
# for the group definitions — Redis is deliberately excluded, because the cache layer
# is fail-open and a Redis outage must not take the API out of rotation.
#
# start-period covers JVM boot + Flyway migration on a cold database.
HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=4 \
    CMD curl --fail --silent --show-error \
        "http://127.0.0.1:${MANAGEMENT_PORT}/actuator/health/readiness" || exit 1

# ENTRYPOINT via `exec` so the JVM becomes PID 1 and receives SIGTERM directly.
# Without `exec`, the shell is PID 1, swallows the signal, and Docker kills the
# container after the grace period — losing in-flight requests and skipping Spring's
# graceful shutdown (server.shutdown=graceful, 30s drain).
# The shell form is required for $JAVA_OPTS word-splitting; the exec undoes its cost.
ENTRYPOINT ["/bin/sh", "-c", "exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher \"$@\"", "--"]
