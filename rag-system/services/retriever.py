from __future__ import annotations

from config.settings import settings
from services.embeddings import embed_texts
from services.vector_store import search


def retrieve(query: str, top_k: int | None = None) -> list[dict]:
    top_k = top_k or settings.default_top_k
    query_embedding = embed_texts([query])[0]
    return search(query_embedding, top_k=top_k)
