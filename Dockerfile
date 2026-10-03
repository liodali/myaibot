# syntax=docker/dockerfile:1

# ---- Stage 1: build a self-contained AOT executable -------------------------
FROM docker.io/library/dart:stable AS build
WORKDIR /app

# Cache dependencies: only re-run pub get when pubspec changes.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY lib lib
COPY bin bin

RUN dart compile exe bin/server.dart -o /app/bot

# ---- Stage 2: minimal runtime ------------------------------------------------
# distroless/cc-debian12: glibc + libstdc++ + CA certificates (needed for the
# outbound HTTPS calls to Chatwoot/LLM APIs), no shell, no package manager.
# ~25 MB base vs ~1 GB for dart:stable.
FROM gcr.io/distroless/cc-debian12:nonroot

WORKDIR /app

COPY --from=build /app/bot /app/bot
# Knowledge base is read from disk at runtime; bake it in.
# (Override by mounting a volume over /app/knowledge.)
COPY knowledge /app/knowledge

# Note: the health check lives in docker-compose.yml so it also works with
# podman's default OCI image format (Dockerfile HEALTHCHECK is ignored there).

ENTRYPOINT ["/app/bot"]
