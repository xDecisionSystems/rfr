from __future__ import annotations

from openai import AzureOpenAI

from config.settings import settings

_client = AzureOpenAI(
    azure_endpoint=settings.azure_openai_endpoint,
    api_key=settings.azure_openai_api_key,
    api_version=settings.azure_openai_api_version,
)

SYSTEM_PROMPT = (
    "You are a research assistant. Answer ONLY from the provided context. "
    "If the answer is not in context, reply exactly: I don't know. "
    "When you answer, include citation markers inline in the form "
    "(source: <filename>, page <number>)."
)


def _render_context(context_chunks: list[dict]) -> str:
    blocks: list[str] = []
    for idx, chunk in enumerate(context_chunks, start=1):
        meta = chunk.get("metadata", {})
        source = meta.get("source", "unknown")
        page = meta.get("page", "?")
        text = chunk.get("text", "").strip()
        if not text:
            continue
        blocks.append(f"[{idx}] source={source}; page={page}\n{text}")
    return "\n\n".join(blocks)


_SLUG_SYSTEM_PROMPT = (
    "You are a filename generator for academic papers. "
    "Return ONLY a snake_case slug — no punctuation, no stop words, lowercase. "
    "The slug must be 4 to 6 meaningful content words joined by underscores. "
    "Output nothing except the slug itself."
)


def simplify_title(title: str) -> str:
    """Return a 4-6 word snake_case slug summarising the paper title."""
    response = _client.chat.completions.create(
        model=settings.chat_deployment_name,
        temperature=0.0,
        messages=[
            {"role": "system", "content": _SLUG_SYSTEM_PROMPT},
            {"role": "user", "content": title},
        ],
    )
    raw = (response.choices[0].message.content or "").strip().lower()
    # Sanitize: keep only word chars and underscores, collapse runs.
    import re
    slug = re.sub(r"[^\w]+", "_", raw).strip("_")
    return slug or "untitled"


def generate_answer(query: str, context_chunks: list[dict]) -> dict:
    if not context_chunks:
        return {"answer": "I don't know.", "sources": []}

    context_text = _render_context(context_chunks)
    user_prompt = (
        f"Question:\n{query}\n\n"
        f"Context:\n{context_text}\n\n"
        "Rules:\n"
        "1) Use only the context above.\n"
        "2) Add citations in this exact style: (source: FILE, page X).\n"
        "3) If context does not answer the question, output exactly: I don't know."
    )

    response = _client.chat.completions.create(
        model=settings.chat_deployment_name,
        temperature=0.0,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )

    answer = (response.choices[0].message.content or "").strip() or "I don't know."

    # Return deduplicated source list used to build retrieval context.
    seen: set[tuple] = set()
    sources: list[dict] = []
    for chunk in context_chunks:
        meta = chunk.get("metadata", {})
        key = (meta.get("source"), meta.get("page"))
        if key in seen:
            continue
        seen.add(key)
        sources.append(
            {
                "source": meta.get("source"),
                "page": meta.get("page"),
                "chunk_id": meta.get("chunk_id"),
                "score": chunk.get("score"),
            }
        )

    return {"answer": answer, "sources": sources}
