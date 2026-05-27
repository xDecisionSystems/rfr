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

## 6. Git Commit Message (Mandatory)

After every change, output a ready-to-use git commit message in this exact format:

```
<type>(<scope>): <short imperative summary under 72 chars>

<body — what changed and why, wrapped at 72 chars. Omit if the
subject line is self-explanatory.>

Files: <comma-separated list of files changed>
Version: <new VERSION_NAME value>
```

**Type** must be one of: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`.
**Scope** is the top-level directory or module affected (e.g. `services`, `api`, `ingestion`, `deploy`, `config`).

Output the commit message in a fenced code block so the user can copy it directly.
Do not suggest committing `.env` or any file matching `.gitignore`.

Examples:

```
feat(api): add POST /simplify-title endpoint for LLM-based title slugging

Files: rag-system/api/main.py, rag-system/services/llm.py, ARCHITECTURE.md
Version: rag-system-v0.1.1
```

```
fix(services): narrow Qdrant UnexpectedResponse catch to 404 only

Re-raises non-404 errors so Qdrant crashes surface instead of
silently returning empty results.

Files: rag-system/services/vector_store.py
Version: rag-system-v0.1.2
```

## 7. Agent Handoff Log (Mandatory)

`AGENT_LOG.md` at the repo root is the shared memory between agents. Every agent that touches this repo must participate in the loop.

**Before starting any task:**
1. Read `AGENT_LOG.md` in full.
2. Note any open items relevant to your task.

**After completing any task:**
1. Prepend a new entry at the top of `AGENT_LOG.md` (newest entry first).
2. Use this exact format:

```markdown
## [YYYY-MM-DD] <agent-name> — <one-line summary>
**Action:** What was done and why.
**Files changed:** List each file modified, created, or deleted.
**Decisions:** Any non-obvious choices made and the reasoning.
**Open items:** Anything left incomplete, deferred, or worth a follow-up.
```

3. If `AGENT_LOG.md` exceeds 200 lines, move all entries older than the 10 most recent into `history/YYYY-MM.md` (create the file if needed), then leave only the 10 most recent entries in `AGENT_LOG.md`.

Do not skip this step. It is how the next agent — human or AI — knows what happened.
