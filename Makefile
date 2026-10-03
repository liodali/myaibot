.PHONY: dev start analyze format install simulate up down logs restart check-env

install:
	dart pub get

dev:
	dart run --enable-vm-service bin/server.dart

start:
	dart run bin/server.dart

analyze:
	dart analyze

format:
	dart format lib bin

# make simulate MSG="How do I reset my password?"
simulate:
	dart run bin/simulate_webhook.dart "$(MSG)"

check-env:
	dart run bin/check_env.dart

# Build the small AOT container image (distroless runtime, ~45 MB).
image:
	podman build -t ai-bot:latest .

up:
	podman-compose up -d --build

down:
	podman-compose down

restart:
	podman-compose restart

logs:
	podman logs -f ai-bot_bot_1
