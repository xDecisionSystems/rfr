# AGENTS.md

Guidance for programming agents contributing to this repository.

## 1. Mission

Maintain a self-hosted research RAG system deployed inside a Debian-based Proxmox LXC container:

- `ingestion/` — PDF loading and chunking pipeline.
- `services/` — embeddings, vector store, retrieval, and LLM answer generation.
- `api/` — FastAPI HTTP interface for ingestion and querying.
- `scripts/` — CLI tools for ingestion and example queries.
- `config/` — environment-driven settings.

Prioritize correctness, safe defaults, and predictable API behavior.

## 2. Repository Scope

```
rag-system/
├── api/
│   └── main.py                  # FastAPI entrypoint (POST /ingest, POST /query, GET /health)
├── ingestion/
│   ├── pdf_loader.py            # PyMuPDF page extraction
│   └── chunker.py               # Paragraph/sentence chunking (~300–500 tokens)
├── services/
│   ├── embeddings.py            # Azure OpenAI embedding calls (batched)
│   ├── vector_store.py          # Qdrant upsert + search
│   ├── retriever.py             # Query → embed → search pipeline
│   └── llm.py                   # Azure OpenAI chat with citation prompt
├── config/
│   └── settings.py              # Dataclass-based settings loaded from .env
├── data/
│   └── papers/                  # Drop PDFs here for ingestion
├── scripts/
│   ├── ingest_folder.py         # CLI: ingest all PDFs in a folder
│   └── query_example.py         # CLI: send a question to the running API
├── deploy/
│   └── qdrant.service           # systemd unit for native Qdrant binary
├── setup.sh                     # Debian base setup + venv creation + pip install
├── install_qdrant.sh            # Download and install Qdrant native binary
├── requirements.txt
└── .env.example
```

If you add or change behavior in any module, update `ARCHITECTURE.md` in the same change if the data flow or component responsibilities change.

## 3. Data Folder

- `data/papers/` is the default PDF ingestion directory.
- The folder is tracked via `.gitkeep`; its contents are git-ignored.
- When testing ingestion, place PDFs in `data/papers/` or pass an explicit path to the CLI/API.
- Do not hardcode paths outside of `config/settings.py`.

## 4. Deployment Policy

- Production: single Debian-based Proxmox LXC with `systemd`.
- Qdrant runs natively from `/opt/qdrant/qdrant` (no Docker).
- Python environment lives at `/opt/rag-env/` (created by `setup.sh`).
- Activate with: `source /opt/rag-env/bin/activate`
- To start the API: `uvicorn api.main:app --host 0.0.0.0 --port 8000`
- Qdrant systemd unit: `deploy/qdrant.service` → copy to `/etc/systemd/system/`.

## 5. Agent Roles

- **Implementer agent**: owns code changes inside `ingestion/`, `services/`, `api/`, `scripts/`, or `config/`.
- **Documentation agent**: owns `README.md`, `ARCHITECTURE.md`, root `.env.example`.
- **Verification agent**: runs syntax checks and smoke tests.

When using multiple agents in parallel, assign disjoint file ownership.

## 6. Coding Rules

- Python 3.10+ compatible syntax.
- Preserve current API contracts unless explicitly asked to break them.
- Keep endpoints deterministic and JSON-serializable.
- Validate all user inputs (paths, questions, top_k).
- Fail with explicit HTTP status and message.
- Keep network calls bounded (Azure OpenAI calls are batched; Qdrant calls use defaults).
- Never log or expose API keys or secrets.
- Keep external dependencies minimal — the full stack needs only what is in `requirements.txt`.
- For standalone scripts, prefer flat top-level execution flow wrapped in `main()` with `if __name__ == "__main__"`.

## 7. Python Environment Rules (Required)

- Virtual environment at `/opt/rag-env/` for production; any local venv is acceptable for development.
- Install deps: `pip install -r requirements.txt`
- Re-run whenever `requirements.txt` changes.
- Do not use system/global `python3` or `pip` for project tasks unless inside the activated venv.

## 8. Version Update Rule

- Whenever code changes are made, automatically increment the patch version in `VERSION.md` at the project root (e.g. `v0.1.0` → `v0.1.1`).
- If the user says `update version name to <new>`, use that exact name instead.
- Format: `VERSION_NAME=<version name>`

## 9. Safety and Security

- Accept only filesystem paths provided explicitly by the caller; do not traverse outside the given folder.
- Treat PDF content as untrusted text — do not execute or eval anything extracted.
- Never write API keys to logs or response bodies.
- Qdrant listens on localhost only by default; do not expose port 6333 externally without authentication.

## 10. Change Workflow

1. Identify which module is affected.
2. Read that module and `config/settings.py`.
3. Implement the smallest coherent change.
4. Run syntax checks for affected files.
5. Update `ARCHITECTURE.md` if data flow or component responsibilities changed.
6. Update `.env.example` if new config keys were added.
7. Summarize changes, assumptions, and residual risks.

## 11. Definition of Done

- Code is syntactically valid.
- Endpoint behavior matches `ARCHITECTURE.md`.
- New config keys are documented in `.env.example`.
- Existing ingestion → retrieval → answer pipeline remains intact unless explicitly changed.
- Risks and follow-ups are stated.
