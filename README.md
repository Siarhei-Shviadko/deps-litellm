# deps-litellm

Standalone [LiteLLM](https://docs.litellm.ai/) proxy for the DEPS platform. This service exposes a unified OpenAI-compatible API over multiple LLM providers (AWS Bedrock, EPAM DIAL, DeepSeek, Groq) with PostgreSQL-backed key and usage storage.

There is no application Python code in this repository—only configuration, Docker Compose, and Helm manifests.

## Prerequisites

1. **Docker network** `deps-network` (created automatically by `make prereq` or `make start`).
2. **Shared PostgreSQL** from `core-services/deps-infra` running on `deps-network`:
   ```bash
   cd ../deps-infra
   make start   # or docker compose up -d postgres
   ```
3. **Database** `litellm` on the shared Postgres instance (create once):
   ```bash
   docker exec -it deps-postgres psql -U deps-postgres -c "CREATE DATABASE litellm;"
   ```

## Local setup

```bash
cd core-services/deps-litellm
make install    # copies .env.example and etc/litellm/.env.example if missing
```

Edit `etc/litellm/.env` and set provider credentials. Never commit real secrets.

| Variable | Purpose |
|----------|---------|
| `LITELLM_MASTER_KEY` | Proxy admin key (must start with `sk-`) |
| `LITELLM_SALT_KEY` | Salt for hashing keys in the database |
| `DATABASE_URL` | PostgreSQL connection (default matches shared infra) |
| `AWS_*` | AWS Bedrock credentials |
| `DIAL_*` | EPAM DIAL proxy (`DIAL_API_BASE`, `DIAL_API_KEY`) |
| `DEEPSEEK_*` | DeepSeek API |
| `GROQ_*` | Groq API |

`etc/litellm/providers.json` documents DIAL `base_url`; set `DIAL_API_BASE` and `DIAL_API_KEY` in `.env` to match your environment.

Start the proxy:

```bash
make start
curl http://localhost:4000/health
```

Stop and view logs:

```bash
make stop
make logs
```

## How other services connect

Services on `deps-network` reach the proxy at:

```
http://deps-litellm:4000
```

Example for **deps-ai-fusion** (via `deps-gen-ai`): set the LiteLLM base URL to `http://deps-litellm:4000` in that service’s environment. No code changes are required if the base URL is already configurable.

Common endpoints:

- `GET /health`
- `POST /v1/chat/completions`
- `POST /v1/embeddings`

Use the master key from `LITELLM_MASTER_KEY` (or `general_settings.master_key` in local `config.yaml`) as the Bearer token.

## Configuration

### Models (`etc/litellm/config.yaml`)

Add a `model_list` entry with `litellm_params` referencing provider settings via `os.environ/VAR_NAME`. Restart the container after changes.

Configured models:

| Model name | Provider |
|------------|----------|
| `bedrock-claude-3-5-sonnet` | AWS Bedrock |
| `bedrock-claude-haiku-4-5` | AWS Bedrock |
| `bedrock-claude-3-sonnet` | AWS Bedrock |
| `dial-gpt-4o` | EPAM DIAL (Azure-compatible) |
| `dial-rag` | EPAM DIAL RAG |
| `deepseek-chat` | DeepSeek |
| `llama-3.1-8b-instant` | Groq |

### Providers (`etc/litellm/providers.json`)

Reference data for provider endpoints. Secrets belong in `etc/litellm/.env`, not in committed JSON.

## Kubernetes (Helm)

```bash
helm lint .helm/services
helm upgrade --install deps-litellm .helm/services \
  -f .helm/services/values.yaml \
  --namespace deps
```

Override `secrets.*` in environment-specific values or inject secrets from your vault/secret manager before deploy. Production should not rely on default placeholder keys in `values.yaml`.

| File | Use |
|------|-----|
| `.helm/services/values.yaml` | Base chart values (dev defaults) |
| `.helm/values.staging.yaml` | Staging |
| `.helm/values.qa.yaml` | QA |
| `.helm/values.demo.yaml` | Demo |
| `.helm/values.ds.yaml` | DS sandbox |
| `.helm/values.ins.yaml` | Insurance |
| `.helm/values.other.yaml` | Other environments |

Service name in the cluster: `deps-litellm` (port 4000).

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│ deps-ai-fusion  │────▶│  deps-litellm    │────▶│  Providers  │
│ (other services)│     │  :4000           │     │ Bedrock/DIAL│
└─────────────────┘     └────────┬─────────┘     └─────────────┘
                                   │
                                   ▼
                          ┌──────────────────┐
                          │ postgres (shared)│
                          │ DB: litellm      │
                          └──────────────────┘
```
