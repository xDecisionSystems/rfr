# RFR — Research RAG System

A self-hosted "ChatGPT for research papers" running fully inside a Debian Proxmox LXC.
No Docker. Uses **Azure OpenAI** for embeddings and chat, **Qdrant** (native binary) for
vector storage, and **FastAPI** for the HTTP API.

**Production URL:** https://rfr.xds-lab.com  
**API docs:** https://rfr.xds-lab.com/docs  
**LLM reference:** https://rfr.xds-lab.com/llms.txt

---

## What it does

```
PDFs → extract → chunk → embed → Qdrant
                                    ↓
Query → embed → vector search → Azure OpenAI → answer + citations
```

- Ingest academic PDFs from a folder via API or CLI
- Ask research questions — answers are grounded in your documents with inline citations
- Generate structured filenames for downloaded papers (`POST /simplify-title`)

---

## Repository layout

```
rfr/
├── rag-system/              # Application code
│   ├── api/
│   │   ├── main.py          # FastAPI app — /health /ingest /query /simplify-title /llms.txt
│   │   └── static/
│   │       └── llms.txt     # LLM-readable API reference (llmstxt.org format)
│   ├── ingestion/
│   │   ├── pdf_loader.py    # PyMuPDF page extraction
│   │   └── chunker.py       # Paragraph/sentence chunking (~300–500 tokens)
│   ├── services/
│   │   ├── embeddings.py    # Azure OpenAI embedding calls (batched)
│   │   ├── vector_store.py  # Qdrant upsert + search
│   │   ├── retriever.py     # Query → embed → search pipeline
│   │   └── llm.py           # Azure OpenAI chat + title simplification
│   ├── config/
│   │   └── settings.py      # Frozen dataclass from .env
│   ├── scripts/
│   │   ├── ingest_folder.py # CLI: ingest PDFs
│   │   └── query_example.py # CLI: query the running API
│   ├── data/papers/         # Drop PDFs here (git-ignored)
│   ├── deploy/
│   │   └── qdrant.service   # systemd unit for Qdrant
│   ├── setup.sh             # Debian base setup + venv + pip install
│   ├── install_qdrant.sh    # Download and install Qdrant native binary
│   ├── requirements.txt
│   └── .env.example
├── deploy/                  # Proxmox deployment scripts
│   ├── proxmox_deploy.sh    # Create LXC and deploy all services
│   ├── restart.sh           # Restart services in dependency order (run inside LXC)
│   └── update.sh            # git pull + pip install + restart (run inside LXC)
├── ARCHITECTURE.md          # Data flow, endpoint contracts, config reference
├── AGENTS.md                # Rules for AI coding agents working on this repo
├── CLAUDE.md                # Claude Code specific instructions
├── AGENT_LOG.md             # Shared agent handoff log (newest entry first)
├── VERSION.md               # Current version
└── .gitignore
```

---

## Quick start (local dev)

### Prerequisites

- Python 3.10+
- [Qdrant](https://qdrant.tech) running locally (see below)
- Azure OpenAI resource with an embedding deployment and a chat deployment

### 1. Install Qdrant natively

```bash
sudo bash rag-system/install_qdrant.sh
/opt/qdrant/qdrant &
```

### 2. Configure environment

```bash
cp rag-system/.env.example rag-system/.env
# edit rag-system/.env — fill in Azure OpenAI keys and deployment names
```

Required keys:

| Variable | Description |
|---|---|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI resource endpoint |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key |
| `EMBEDDING_DEPLOYMENT_NAME` | Embedding model deployment (e.g. `text-embedding-3-large`) |
| `CHAT_DEPLOYMENT_NAME` | Chat model deployment (e.g. `gpt-4o-mini`) |

### 3. Create venv and install dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r rag-system/requirements.txt
```

### 4. Start the API

```bash
cd rag-system
uvicorn api.main:app --host 127.0.0.1 --port 8000
```

### 5. Ingest papers

Place PDFs in `rag-system/data/papers/`, then:

```bash
# via CLI
python rag-system/scripts/ingest_folder.py rag-system/data/papers

# or via API
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"folder_path": "data/papers"}'
```

### 6. Ask a question

```bash
# via CLI
python rag-system/scripts/query_example.py "What trajectory optimization methods are used for UAVs?"

# or via API
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"question": "What trajectory optimization methods are used for UAVs?", "top_k": 5}'
```

Response:

```json
{
  "answer": "UAV trajectory optimization commonly uses ... (source: paper.pdf, page 3)",
  "sources": [
    {"source": "paper.pdf", "page": 3, "chunk_id": "paper-p3-c1-abc123", "score": 0.91}
  ]
}
```

---

## API reference

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Liveness check |
| `POST` | `/ingest` | Ingest PDFs from a folder into Qdrant |
| `POST` | `/query` | Answer a research question with citations |
| `POST` | `/simplify-title` | Generate a structured filename slug from paper metadata |
| `GET` | `/llms.txt` | LLM-readable API reference |

### `POST /simplify-title`

Generates a filename of the form `<title_slug>-<last_name>-<venue_acronym>-<YYYY>`.

```bash
curl -X POST http://localhost:8000/simplify-title \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Attention Is All You Need",
    "author": "Ashish Vaswani",
    "venue": "Neural Information Processing Systems",
    "year": 2017
  }'
```

```json
{
  "title": "Attention Is All You Need",
  "author": "Ashish Vaswani",
  "venue": "Neural Information Processing Systems",
  "year": 2017,
  "filename": "attention_transformer_architecture-vaswani-neurips-2017"
}
```

Only `title` is required. Omitted fields are excluded from the filename.

Full interactive docs at https://rfr.xds-lab.com/docs.

---

## Proxmox LXC deployment

### Fresh deploy

Run from your local machine. Creates the LXC, installs Qdrant natively, clones the repo,
sets up the venv, installs both services as systemd units, and health-checks everything.

```bash
./deploy/proxmox_deploy.sh
```

Options (all prompted interactively if not set):

```
--proxmox-host   Proxmox SSH target
--repo-url       Git repo URL (https://github.com/xDecisionSystems/rfr)
--repo-branch    Branch to deploy (default: main)
--ip             Static IP/CIDR or dhcp (default: dhcp)
--dry-run        Preview all actions without executing
```

### Update a running deployment

Run as root **inside the LXC**:

```bash
bash /opt/rag-system/deploy/update.sh
# or: pct exec <vmid> -- bash /opt/rag-system/deploy/update.sh
```

Pulls latest code, reinstalls dependencies, restarts services with health checks.

### Restart services

```bash
bash /opt/rag-system/deploy/restart.sh           # restart all
bash /opt/rag-system/deploy/restart.sh --status  # show status only
```

Service dependency order: `qdrant` → `rag-api`.

---

## Configuration reference

All settings via `.env` (see `rag-system/.env.example`):

| Variable | Required | Default | Description |
|---|---|---|---|
| `AZURE_OPENAI_ENDPOINT` | yes | — | Azure OpenAI resource endpoint |
| `AZURE_OPENAI_API_KEY` | yes | — | Azure OpenAI API key |
| `AZURE_OPENAI_API_VERSION` | no | `2024-02-15-preview` | API version |
| `EMBEDDING_DEPLOYMENT_NAME` | yes | — | Embedding model deployment name |
| `CHAT_DEPLOYMENT_NAME` | yes | — | Chat model deployment name |
| `QDRANT_HOST` | no | `localhost` | Qdrant host |
| `QDRANT_PORT` | no | `6333` | Qdrant port |
| `QDRANT_COLLECTION` | no | `research_papers` | Collection name |
| `DEFAULT_TOP_K` | no | `5` | Default retrieval chunk count |
| `EMBEDDING_BATCH_SIZE` | no | `64` | Chunks per embedding API call |

---

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md) — detailed data flow, chunking strategy, Qdrant schema, deployment topology
- [AGENTS.md](AGENTS.md) — rules for AI coding agents (change workflow, commit format, version bumping)
- [AGENT_LOG.md](AGENT_LOG.md) — shared handoff log between agents
- [rfr.xds-lab.com/llms.txt](https://rfr.xds-lab.com/llms.txt) — machine-readable API reference
