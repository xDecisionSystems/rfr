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


import re

_TITLE_SLUG_PROMPT = (
    "You are a filename generator for academic papers. "
    "Given a paper title, return ONLY a snake_case slug: lowercase, no stop words, "
    "3 to 5 meaningful content words joined by underscores. "
    "Output nothing except the slug itself."
)

_VENUE_SLUG_PROMPT = (
    "You are a filename generator for academic papers. "
    "Given a journal or conference name, return ONLY its standard abbreviation or acronym "
    "in lowercase with no spaces or punctuation (e.g. 'ieee_tro', 'neurips', 'icra', 'nature'). "
    "If it is already short, just lowercase and snake_case it. "
    "Output nothing except the slug itself."
)


def _llm_slug(system_prompt: str, user_text: str) -> str:
    response = _client.chat.completions.create(
        model=settings.chat_deployment_name,
        temperature=0.0,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text},
        ],
    )
    raw = (response.choices[0].message.content or "").strip().lower()
    return re.sub(r"[^\w]+", "_", raw).strip("_")


def _author_slug(author: str) -> str:
    """Extract the last name from 'First Last' or 'Last, First' and slugify it."""
    author = author.strip()
    if "," in author:
        last = author.split(",")[0]
    else:
        last = author.split()[-1] if author else author
    return re.sub(r"[^\w]+", "_", last.lower()).strip("_")


def simplify_title(
    title: str,
    author: str = "",
    venue: str = "",
    year: int | None = None,
) -> str:
    """Return a compound filename slug: <title>-<author>-<venue>-<year>."""
    title_slug = _llm_slug(_TITLE_SLUG_PROMPT, title) or "untitled"

    parts = [title_slug]

    if author:
        parts.append(_author_slug(author) or "unknown")

    if venue:
        venue_slug = _llm_slug(_VENUE_SLUG_PROMPT, venue) or re.sub(r"[^\w]+", "_", venue.lower()).strip("_")
        parts.append(venue_slug)

    if year:
        parts.append(str(year))

    return "-".join(parts)


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
