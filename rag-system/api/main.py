from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from config.settings import settings
from ingestion.chunker import chunk_pages
from ingestion.pdf_loader import load_pdf
from services.embeddings import embed_texts
from services.llm import generate_answer, simplify_title
from services.retriever import retrieve
from services.vector_store import upsert

app = FastAPI(title="Research RAG API", version="1.0.0")


class IngestRequest(BaseModel):
    folder_path: str = Field(default=str(settings.default_papers_dir))


class QueryRequest(BaseModel):
    question: str
    top_k: int = Field(default=settings.default_top_k, ge=1, le=20)


class SimplifyTitleRequest(BaseModel):
    title: str


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/simplify-title")
def simplify_title_endpoint(request: SimplifyTitleRequest) -> dict:
    title = request.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title cannot be empty")
    try:
        slug = simplify_title(title)
        return {"title": title, "slug": slug}
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Title simplification failed: {exc}",
        ) from exc


@app.post("/ingest")
def ingest_documents(request: IngestRequest) -> dict:
    folder = Path(request.folder_path).expanduser().resolve()
    if not folder.exists() or not folder.is_dir():
        raise HTTPException(status_code=400, detail=f"Invalid folder path: {folder}")

    pdf_paths = sorted(folder.rglob("*.pdf"))
    if not pdf_paths:
        raise HTTPException(status_code=404, detail=f"No PDF files found in {folder}")

    all_chunks: list[dict] = []
    file_stats: list[dict] = []

    for pdf_path in pdf_paths:
        pages = load_pdf(str(pdf_path))
        chunks = chunk_pages(pages)
        if chunks:
            all_chunks.extend(chunks)
        file_stats.append(
            {
                "source": pdf_path.name,
                "pages": len(pages),
                "chunks": len(chunks),
            }
        )

    if not all_chunks:
        raise HTTPException(status_code=400, detail="No extractable text chunks were created.")

    try:
        embeddings = embed_texts([chunk["text"] for chunk in all_chunks])
        upserted = upsert(all_chunks, embeddings)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Ingestion failed during embedding/vector store step: {exc}",
        ) from exc

    return {
        "status": "ok",
        "ingested_pdfs": len(pdf_paths),
        "chunks": len(all_chunks),
        "upserted": upserted,
        "files": file_stats,
    }


@app.post("/query")
def query_documents(request: QueryRequest) -> dict:
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="question cannot be empty")

    try:
        context_chunks = retrieve(question, top_k=request.top_k)
        result = generate_answer(question, context_chunks)
        return result
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Query pipeline failed (retrieval/generation): {exc}",
        ) from exc
