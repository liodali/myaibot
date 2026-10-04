# MyAIBot — AI first-line support for Chatwoot

A small, dependency-light **Chatwoot Agent Bot** service built with **Dart +
[Relic](https://pub.dev/packages/relic)** (v2 release candidate) that auto-answers
customer messages using any **OpenAI-compatible LLM API** (Groq, OpenRouter,
DeepSeek, OpenAI, Mistral, Together…). No Ollama, no GPU, no enterprise plan
required.

```
Customer msg → Chatwoot inbox → HTTP POST (webhook) → this service
      ↑                                                    │
      └──── POST reply via Agent Bot API ←────────── LLM API (hosted)
```

## Why this design

- **Lightweight:** one Dart process, small memory footprint, no database of its own.
- **Own your stack:** inbox, prompts, knowledge and logic are yours; only the
  model inference is rented (swap providers any time without touching Chatwoot).
- **Works with fully-OSS Chatwoot** — replaces the paid "Captain" AI add-on.
- **No public endpoint needed:** it can run on the same Podman network as
  Chatwoot and be reached at `http://ai-bot:3000/webhook`.

## Requirements

- [Dart SDK](https://dart.dev/get-dart) >= 3.7 **or** Podman/Docker
- A running Chatwoot instance + an admin **user** access token
- An LLM API key (any OpenAI-compatible endpoint)

## Quick start (local)

```bash
cp .env.example .env
# edit .env: set BOT_TOKEN, BOT_SECRET (or leave blank for local), LLM_API_KEY
dart pub get
dart run bin/server.dart       # starts the webhook server on :3000
```

In another shell, simulate a Chatwoot webhook (signs the payload if `BOT_SECRET` is set):

```bash
BOT_SECRET=your_secret dart run bin/simulate_webhook.dart "How do I reset my password?"
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind address (keep `0.0.0.0` inside containers) |
| `PORT` | `3000` | HTTP port |
| `CHATWOOT_URL` | `http://chatwoot_rails_1:3000` | Internal or public Chatwoot base URL |
| `BOT_TOKEN` | — | **Agent Bot** access token |
| `BOT_SECRET` | — | Agent Bot secret, used to verify webhook signatures |
| `LLM_BASE_URL` | `https://api.groq.com/openai/v1` | OpenAI-compatible base URL |
| `LLM_MODEL` | `llama-3.3-70b-versatile` | Model name |
| `LLM_API_KEY` | — | Provider API key |
| `LLM_TEMPERATURE` | `0.3` | Sampling temperature |
| `LLM_MAX_TOKENS` | `500` | Max reply tokens |
| `SYSTEM_PROMPT` | built-in | Bot persona/instructions |
| `KNOWLEDGE_FILE` | `knowledge/faq.md` | Markdown KB injected into the prompt |
| `MAX_HISTORY` | `10` | Past messages sent as context |
| `ONLY_WHEN_PENDING` | `true` | Stop replying once a human takes over |
| `HANDOFF_KEYWORD` | `[HANDOFF]` | Escalation token the model can emit |

## Create the Chatwoot bot

Get an admin **user token** from Chatwoot (Profile → Access Token), then:

```bash
export CHATWOOT_URL=https://chatwoot.example.com
export ACCOUNT_ID=1
export USER_TOKEN=...
export BOT_NAME="AI Support Bot"
# If this service runs next to Chatwoot on the same Podman network:
export OUTGOING_URL=http://ai-bot:3000/webhook

bash scripts/create-chatwoot-bot.sh   # writes bot.json (id, access_token, secret)
```

Copy `access_token` → `BOT_TOKEN` and `secret` → `BOT_SECRET` in `.env`, then attach
the bot to an inbox:

```bash
export INBOX_ID=3
export BOT_ID=$(jq -r .id bot.json)   # or read bot.json manually
bash scripts/attach-bot-to-inbox.sh
```

## Run with Podman (next to Chatwoot)

The compose file builds a **multi-stage image**: the Dart server is AOT-compiled
to a native executable and shipped in a distroless runtime — **~45 MB total**
(vs ~1 GB for a Dart-SDK-based image). No source mounts, no SDK in production.

```bash
podman-compose up -d --build
podman logs -f ai-bot_bot_1
```

To iterate on the knowledge base without rebuilding, mount it:
`podman run -v ./knowledge:/app/knowledge ...` (hint included in docker-compose.yml).

The compose file joins the external `chatwoot_internal` network with the alias
`ai-bot`, so Chatwoot's Sidekiq worker reaches `http://ai-bot:3000/webhook`
directly — no public exposure, no TLS. To expose publicly instead, put it behind
Traefik and set `OUTGOING_URL` to that hostname.

## Customizing

- **Knowledge base:** edit `projects/<name>/knowledge/faq.md` — it is injected into the system prompt.
- **Persona:** change `SYSTEM_PROMPT`.
- **Escalation:** the model is told to emit `[HANDOFF]` when unsure; the bot then
  posts a private note and reopens the conversation for a human.
- **Human takeover:** with `ONLY_WHEN_PENDING=true`, the bot goes quiet as soon as
  the conversation status is no longer `pending`.

## Security notes

- Always set `BOT_SECRET`. Requests are verified with
  `HMAC-SHA256(secret, "<timestamp>.<raw_body>")` (timing-safe compare).
- Use the **Agent Bot** access token (not a user token) so replies post as the bot.
- Keep `.env` and `bot.json` out of git (they are ignored).

## Deployment

Production deploys run through **GitHub → Gitea pull-mirror → Jenkins**
(never builds fork PRs; pipeline pinned to `main`). See [docs/deploy.md](docs/deploy.md)
for the full wiring, and [jenkins/](jenkins/) for the Job DSL seed.

## Multiple projects (one bot, routed by chat)

One bot container serves every app. Chatwoot routes each chat by inbox: one
Agent Bot is attached to **all** inboxes, every event carries `inbox.id`,
and `PROJECTS_MAP` selects that project's knowledge base:

```
PROJECTS_MAP=9:wasfa                                    # exact inbox id (wins)
PROJECTS_NAME_MAP=sovereign:sovereignledger,\
                   api.exchange:exchangeconvertapp,\
                   wasfa:wasfa                          # inbox-name substring
DEFAULT_PROJECT=default                                 # everything else
```

- Per-project knowledge: `projects/<name>/knowledge/faq.md` (baked into the
  image at build time)
- Optional per-project persona: `projects/<name>/persona.md` (falls back to
  `SYSTEM_PROMPT`)
- New project = add the folder + a map entry + redeploy
- Unmapped inbox or missing FAQ → the bot answers with persona only and
  escalates unknowns to a human

## Extending

- Add retrieval/RAG (Chatwoot's Postgres already ships `pgvector`).
- Add tool calls (order status, ticket lookup, account actions).

## Project layout

```
bin/server.dart            # Relic entrypoint: GET /health, POST /webhook
bin/simulate_webhook.dart  # signed fake-webhook sender (dev tool)
bin/healthcheck.dart       # container healthcheck
bin/check_env.dart         # print effective config
lib/src/config.dart        # env + .env loading
lib/src/signature.dart     # HMAC-SHA256 webhook verification
lib/src/handler.dart       # dedup, history, LLM reply, [HANDOFF]
lib/src/chatwoot.dart      # Chatwoot Agent Bot API client
lib/src/llm.dart           # OpenAI-compatible chat client
lib/src/prompt.dart        # system prompt + knowledge base
Dockerfile                 # multi-stage: AOT exe → distroless (~45 MB)
scripts/*.sh               # Chatwoot bot setup (curl)
```
