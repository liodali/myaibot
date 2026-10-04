# ---- Stage 1: build a self-contained AOT executable -------------------------
FROM docker.io/library/dart:stable AS build
WORKDIR /app

# Cache dependencies: only re-run pub get when pubspec changes.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY lib lib
COPY bin bin

# Analyze gates the build: warnings/infos fail the image compile.
RUN dart pub get && dart analyze --fatal-infos

RUN dart compile exe bin/server.dart -o /app/bot

# ---- Stage 2: minimal runtime ------------------------------------------------
# distroless/cc-debian12: glibc + libstdc++ + CA certificates (needed for the
# outbound HTTPS calls to Chatwoot/LLM APIs), no shell, no package manager.
# ~25 MB base vs ~1 GB for dart:stable.
FROM gcr.io/distroless/cc-debian12:nonroot

WORKDIR /app

COPY --from=build /app/bot /app/bot
# ALL projects' knowledge baked in (podman service on the deploy host
# rejects bind mounts, so runtime mounting is not an option). Routing is
# by inbox id at runtime — see PROJECTS_MAP in .env.
COPY projects /app/projects

# Note: the health check lives in docker-compose.yml so it also works with
# podman's default OCI image format (Dockerfile HEALTHCHECK is ignored there).

ENTRYPOINT ["/app/bot"]
