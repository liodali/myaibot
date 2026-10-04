# Changelog

## v3.0.0 — Multi-tenant routing (2026-10)

One bot serves every project; the chat's inbox picks the knowledge base.

- **Routing** by webhook inbox: `PROJECTS_MAP` (exact id, wins) →
  `PROJECTS_NAME_MAP` (inbox-name substring, case-insensitive) →
  `DEFAULT_PROJECT`
- Per-project knowledge at `projects/<name>/knowledge/faq.md`, all baked
  into one image; optional per-project `persona.md`
- Starter FAQs: `default`, `wasfa`, `exchangeconvertapp`, `sovereignledger`
- Unmapped inbox / missing FAQ → persona-only answers + human escalation
- Smoke test simulates routing (`INBOX_ID`, `INBOX_NAME`)
- **Breaking config**: `KNOWLEDGE_FILE` removed → `PROJECTS_ROOT`,
  `PROJECTS_MAP`, `PROJECTS_NAME_MAP`, `DEFAULT_PROJECT`
- Fix: send `X-Forwarded-Proto: https` on Chatwoot API calls (Rails
  `FORCE_SSL` 301-redirected direct internal calls to a TLS-less endpoint)
- Images now also carry a `v<version>` registry tag

## v2.0.0 — Dart + Relic rewrite (2026-10)

- Bun/TypeScript service rewritten in Dart on the
  [Relic](https://pub.dev/packages/relic) web framework (2.0.0-rc.2)
- Same behavior: HMAC-verified Chatwoot webhooks, OpenAI-compatible LLM
  replies, `[HANDOFF]` escalation, human-takeover respect
- Ships as a ~44 MB distroless AOT container (multi-stage Dockerfile);
  the binary doubles as its own container healthcheck (`--healthcheck`)
- CI/CD: GitHub → Gitea pull-mirror → Jenkins (REST/JCasC-free bootstrap,
  DslScriptLoader seed) → Gitea container registry → podman-socket deploy
- Fork-PR-proof pipeline: job definition pinned to the mirror's `main`,
  webhook token-gated and filtered to `refs/heads/main`
