from __future__ import annotations

from typing import Any
from uuid import NAMESPACE_URL, uuid5

from qdrant_client import QdrantClient
from qdrant_client.http.exceptions import UnexpectedResponse
from qdrant_client.http import models

from config.settings import settings

client = QdrantClient(host=settings.qdrant_host, port=settings.qdrant_port)


def _ensure_collection(vector_size: int) -> None:
    existing = {c.name for c in client.get_collections().collections}
    if settings.qdrant_collection in existing:
        return

    client.create_collection(
        collection_name=settings.qdrant_collection,
        vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE),
    )


def upsert(chunks: list[dict], embeddings: list[list[float]]) -> int:
    if not chunks:
        return 0
    if len(chunks) != len(embeddings):
        raise ValueError("chunks and embeddings must have the same length")

    _ensure_collection(len(embeddings[0]))

    points: list[models.PointStruct] = []
    for chunk, embedding in zip(chunks, embeddings):
        metadata = dict(chunk.get("metadata", {}))
        payload: dict[str, Any] = {
            "text": chunk.get("text", ""),
            **metadata,
        }
        chunk_id = metadata.get("chunk_id")
        if not chunk_id:
            raise ValueError("Each chunk must include metadata.chunk_id")

        point_uuid = str(uuid5(NAMESPACE_URL, str(chunk_id)))

        points.append(
            models.PointStruct(
                id=point_uuid,
                vector=embedding,
                payload=payload,
            )
        )

    client.upsert(collection_name=settings.qdrant_collection, points=points, wait=True)
    return len(points)


def search(query_embedding: list[float], top_k: int = 5) -> list[dict]:
    try:
        hits = client.search(
            collection_name=settings.qdrant_collection,
            query_vector=query_embedding,
            limit=top_k,
            with_payload=True,
        )
    except UnexpectedResponse as exc:
        # 404 means the collection doesn't exist yet (no documents ingested).
        if str(getattr(exc, "status_code", "")) == "404":
            return []
        raise

    results: list[dict] = []
    for hit in hits:
        payload = hit.payload or {}
        results.append(
            {
                "score": hit.score,
                "text": payload.get("text", ""),
                "metadata": {
                    "source": payload.get("source"),
                    "page": payload.get("page"),
                    "chunk_id": payload.get("chunk_id"),
                },
            }
        )

    return results
