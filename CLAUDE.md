# CLAUDE.md

Repository instructions for Claude-based programming agents.

## Repository Structure

A self-hosted research RAG system deployed in a single Proxmox LXC. No Docker. All components run natively:

- `ingestion/` — PDF text extraction and chunking
- `services/` — Azure OpenAI embeddings + Qdrant vector store + LLM answer generation
- `api/` — FastAPI service (port 8000)
- `scripts/` — CLI ingestion and query tools
- `config/` — environment-driven settings dataclass
- `deploy/` — systemd unit for Qdrant

## Deployment Policy

- Production: Debian-based Proxmox LXC with `systemd`.
- Python environment: `/opt/rag-env/` (created by `setup.sh`).
- Qdrant binary: `/opt/qdrant/qdrant` (installed by `install_qdrant.sh`).
- Shared env lives at `.env` in the project root; `.env.example` documents all keys.
- Local venv + uvicorn is allowed for testing and validation only.
- Do not add additional deployment targets unless explicitly requested.

## 1. Environment Requirement (Mandatory)

- Production venv: `/opt/rag-env/`
- Local development: any venv at the project root is acceptable.
- Install deps: `pip install -r requirements.txt`
- Re-run whenever `requirements.txt` changes.
- Do not use system/global `python3` or `pip` for project tasks.
- Prefer explicit venv activation: `source /opt/rag-env/bin/activate`

## 2. Standard Command Patterns

- Install deps: `pip install -r requirements.txt`
- Run API locally: `uvicorn api.main:app --host 127.0.0.1 --port 8000`
- Ingest PDFs (CLI): `python scripts/ingest_folder.py data/papers`
- Example query (CLI): `python scripts/query_example.py "What is the main contribution?"`
- Syntax check all modules:
  ```
  python -m py_compile api/main.py ingestion/pdf_loader.py ingestion/chunker.py \
    services/embeddings.py services/vector_store.py services/retriever.py services/llm.py \
    config/settings.py scripts/ingest_folder.py scripts/query_example.py
  ```
- Start Qdrant: `/opt/qdrant/qdrant`

## 3. Version Update Rule

- Whenever code changes are made, automatically increment the patch version in `VERSION.md` at the project root (e.g. `v0.1.0` → `v0.1.1`).
- If the user says `update version name to <new version name>`, use that exact name instead.
- Format: `VERSION_NAME=<version name>`
- Keep the key name exactly `VERSION_NAME`.

## 4. Change Hygiene

- When code changes affect behavior, update `ARCHITECTURE.md` in the same change if data flow or component responsibilities changed.
- Keep API responses stable unless a breaking change is explicitly requested.
- Validate all input and return clear HTTP errors.
- Update `.env.example` whenever new config keys are introduced.

## 5. Security Basics

- Never expose API keys or secrets in logs or responses.
- Treat PDF content as untrusted text.
- Qdrant should only listen on localhost (port 6333) — do not expose externally without authentication.
- Do not execute or eval anything extracted from PDFs.
