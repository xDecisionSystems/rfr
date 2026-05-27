# ARCHITECTURE.md

Architecture overview for the Research RAG System.

## 1. High-Level Design

Single-service HTTP API built with FastAPI, backed by a native Qdrant vector store and Azure OpenAI.

Core responsibilities:

- Ingest academic PDFs: extract text, chunk, embed, and store in Qdrant.
- Answer research questions: embed query, retrieve relevant chunks, generate grounded answer with citations via Azure OpenAI.

The implementation is modular:

- `api/main.py` defines FastAPI routes.
- `ingestion/` handles PDF loading and text chunking.
- `services/` contains all external integrations (Azure OpenAI, Qdrant) and the retrieval pipeline.
- `config/settings.py` centralizes environment-driven settings.

## 2. Runtime Components

- **FastAPI app** (`api/main.py`): defines HTTP routes and handles request validation.
- **PDF loader** (`ingestion/pdf_loader.py`): extracts per-page text and metadata using PyMuPDF.
- **Chunker** (`ingestion/chunker.py`): splits page text into ~300–500 token chunks by paragraph and sentence boundary; assigns stable `chunk_id` hashes.
- **Embeddings** (`services/embeddings.py`): calls Azure OpenAI embeddings deployment in configurable batches; returns `list[list[float]]`.
- **Vector store** (`services/vector_store.py`): connects to local Qdrant; lazily creates the collection on first upsert; provides `upsert` and `search`.
- **Retriever** (`services/retriever.py`): thin pipeline — embed query → vector search → return top-k chunks.
- **LLM** (`services/llm.py`): calls Azure OpenAI chat deployment with a citation-enforcing prompt; returns answer text and deduplicated source list.
- **Settings** (`config/settings.py`): frozen dataclass loaded once at import time from environment / `.env` file. Missing required keys raise `RuntimeError` at startup.

## 3. Request Flow

### Ingestion (`POST /ingest`)

```
folder_path → glob PDFs → load_pdf() → chunk_pages() → embed_texts() → upsert() → stats
```

1. Resolve and validate `folder_path`.
2. For each PDF: extract pages with PyMuPDF, chunk into ~300–500 token segments.
3. Batch-embed all chunks via Azure OpenAI.
4. Upsert vectors + payloads into Qdrant (collection auto-created on first call).
5. Return ingestion stats (pdf count, chunk count, upserted count, per-file breakdown).

### Query (`POST /query`)

```
question → embed_texts([question]) → qdrant.search() → generate_answer() → answer + sources
```

1. Embed the question using the same Azure OpenAI deployment as ingestion.
2. Search Qdrant for the top-k most similar chunks.
3. Build a context block from retrieved chunks (numbered, with source/page labels).
4. Call Azure OpenAI chat model with a strict citation prompt.
5. Return answer text and deduplicated source list `[{source, page, chunk_id, score}]`.

### Title Simplification (`POST /simplify-title`)

```
title(+optional author/venue/year) → simplify_title() → structured filename slug
```

1. Validate `title` is non-empty.
2. Generate a title slug with Azure OpenAI chat.
3. Optionally append author last name slug, venue acronym slug, and year.
4. Return a compound filename string for downstream paper-library workflows.

## 4. Endpoint Map

- `GET /health` — liveness check; returns `{"status": "ok"}`.
- `GET /llms.txt` — static `llms.txt` descriptor served from `api/static/llms.txt` with `text/plain` media type.
- `POST /simplify-title` — body: `{"title": "...", "author": "...", "venue": "...", "year": 2024}` where only `title` is required. Returns `{"title": "...", "author": "...", "venue": "...", "year": 2024, "filename": "<title_slug>-<last_name>-<venue_acronym>-<YYYY>"}`.
- `POST /ingest` — body: `{"folder_path": "<path>"}` (default: `data/papers/`). Loads all PDFs in the folder, chunks, embeds, and stores them.
- `POST /query` — body: `{"question": "<text>", "top_k": 5}`. Returns `{"answer": "<text>", "sources": [...]}`.

## 5. Data Contracts

### `/ingest` response

```json
{
  "status": "ok",
  "ingested_pdfs": 3,
  "chunks": 142,
  "upserted": 142,
  "files": [
    {"source": "paper.pdf", "pages": 12, "chunks": 47}
  ]
}
```

### `/query` response

```json
{
  "answer": "... (source: paper.pdf, page 3)",
  "sources": [
    {"source": "paper.pdf", "page": 3, "chunk_id": "paper-p3-c1-abc123", "score": 0.91}
  ]
}
```

### `/simplify-title` response

```json
{
  "title": "A Very Long Research Paper Title",
  "author": "Jane Doe",
  "venue": "Conference on Neural Information Processing Systems",
  "year": 2024,
  "filename": "long_research_title-doe-neurips-2024"
}
```

### Chunk payload stored in Qdrant

```json
{
  "text": "...",
  "source": "paper.pdf",
  "page": 3,
  "chunk_id": "paper-p3-c1-abc123"
}
```

## 6. Configuration Model

All configuration is environment-driven via `.env`. See `.env.example` for the full list.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `AZURE_OPENAI_ENDPOINT` | yes | — | Azure OpenAI resource endpoint |
| `AZURE_OPENAI_API_KEY` | yes | — | Azure OpenAI API key |
| `AZURE_OPENAI_API_VERSION` | no | `2024-02-15-preview` | API version |
| `EMBEDDING_DEPLOYMENT_NAME` | yes | — | Embedding model deployment name |
| `CHAT_DEPLOYMENT_NAME` | yes | — | Chat model deployment name |
| `QDRANT_HOST` | no | `localhost` | Qdrant host |
| `QDRANT_PORT` | no | `6333` | Qdrant port |
| `QDRANT_COLLECTION` | no | `research_papers` | Collection name |
| `DEFAULT_TOP_K` | no | `5` | Default retrieval count |
| `EMBEDDING_BATCH_SIZE` | no | `64` | Chunks per embedding API call |

## 7. Chunking Strategy

- Input: raw page text from PyMuPDF.
- Primary split: double-newline paragraph boundaries (`\n\n`).
- Fallback: single-line split for PDFs with poor paragraph structure.
- Large paragraphs are further split at sentence boundaries (`[.!?]\s+`).
- Token estimate: `words × 1.3` (fast approximation, no tokenizer dependency).
- Target: 380 tokens; hard max: 500 tokens per chunk.
- Chunk ID: `{stem}-p{page}-c{index}-{sha1[:10]}` — stable across re-ingestion of identical text.

## 8. Deployment Topology

- Single Debian-based Proxmox LXC with systemd.
- Qdrant runs natively: `/opt/qdrant/qdrant` (no Docker).
- Python environment: `/opt/rag-env/` (venv).
- systemd unit for Qdrant: `deploy/qdrant.service` → `/etc/systemd/system/qdrant.service`.
- API server: `uvicorn api.main:app --host 0.0.0.0 --port 8000`.
- Qdrant listens on `localhost:6333` only.

## 9. Security Considerations

- Folder path in `/ingest` is resolved and validated before use; only existing directories are accepted.
- PDF content is treated as untrusted text — never executed or eval'd.
- API keys are read from environment variables; never logged or returned in responses.
- Qdrant is bound to localhost by default; do not expose port 6333 externally without authentication.

## 10. Planned Enhancements (Not Yet Implemented)

- **Level 2**: metadata filtering (year, venue), section-aware chunking, CLI query interface.
- **Level 3**: hybrid search (BM25 + vector), re-ranking, multi-hop retrieval.
- **Level 4**: Streamlit UI, arXiv ingestion pipeline, paper comparison mode, citation graph analysis.
