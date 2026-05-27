from __future__ import annotations

import hashlib
import re
from pathlib import Path

TOKENS_PER_WORD = 1.3
TARGET_TOKENS = 380
MAX_TOKENS = 500


def _estimate_tokens(text: str) -> int:
    words = len(text.split())
    return max(1, int(words * TOKENS_PER_WORD))


def _split_paragraphs(text: str) -> list[str]:
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    if paragraphs:
        return paragraphs
    # Fallback for PDFs with sparse/newline-poor extraction.
    return [line.strip() for line in text.splitlines() if line.strip()]


def _split_large_piece(text: str, max_tokens: int) -> list[str]:
    if _estimate_tokens(text) <= max_tokens:
        return [text]

    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]
    if not sentences:
        return [text]

    pieces: list[str] = []
    current: list[str] = []
    current_tokens = 0

    for sentence in sentences:
        sentence_tokens = _estimate_tokens(sentence)
        if current and current_tokens + sentence_tokens > max_tokens:
            pieces.append(" ".join(current))
            current = [sentence]
            current_tokens = sentence_tokens
        else:
            current.append(sentence)
            current_tokens += sentence_tokens

    if current:
        pieces.append(" ".join(current))

    return pieces


def _build_chunk_id(source: str, page: int, chunk_index: int, text: str, file_path: str = "") -> str:
    stem = Path(source).stem.replace(" ", "_")
    digest_input = f"{file_path}|{page}|{chunk_index}|{text}"
    digest = hashlib.sha1(digest_input.encode("utf-8")).hexdigest()[:10]
    return f"{stem}-p{page}-c{chunk_index}-{digest}"


def chunk_pages(
    pages: list[dict],
    target_tokens: int = TARGET_TOKENS,
    max_tokens: int = MAX_TOKENS,
) -> list[dict]:
    """Chunk page text by paragraph/semantic boundaries into ~300-500 token chunks."""
    chunks: list[dict] = []
    doc_chunk_index = 0

    for page in pages:
        buffer: list[str] = []
        buffer_tokens = 0

        paragraphs = _split_paragraphs(page.get("text", ""))

        for paragraph in paragraphs:
            for piece in _split_large_piece(paragraph, max_tokens):
                piece_tokens = _estimate_tokens(piece)

                if buffer and buffer_tokens + piece_tokens > max_tokens:
                    doc_chunk_index += 1
                    text = "\n\n".join(buffer).strip()
                    if text:
                        chunks.append(
                            {
                                "text": text,
                                "metadata": {
                                    "source": page["source"],
                                    "page": page["page"],
                                    "chunk_id": _build_chunk_id(
                                        page["source"],
                                        page["page"],
                                        doc_chunk_index,
                                        text,
                                        page.get("file_path", ""),
                                    ),
                                },
                            }
                        )
                    buffer = [piece]
                    buffer_tokens = piece_tokens
                else:
                    buffer.append(piece)
                    buffer_tokens += piece_tokens

                if buffer_tokens >= target_tokens:
                    doc_chunk_index += 1
                    text = "\n\n".join(buffer).strip()
                    if text:
                        chunks.append(
                            {
                                "text": text,
                                "metadata": {
                                    "source": page["source"],
                                    "page": page["page"],
                                    "chunk_id": _build_chunk_id(
                                        page["source"],
                                        page["page"],
                                        doc_chunk_index,
                                        text,
                                        page.get("file_path", ""),
                                    ),
                                },
                            }
                        )
                    buffer = []
                    buffer_tokens = 0

        if buffer:
            doc_chunk_index += 1
            text = "\n\n".join(buffer).strip()
            if text:
                chunks.append(
                    {
                        "text": text,
                        "metadata": {
                            "source": page["source"],
                            "page": page["page"],
                            "chunk_id": _build_chunk_id(
                                page["source"],
                                page["page"],
                                doc_chunk_index,
                                text,
                                page.get("file_path", ""),
                            ),
                        },
                    }
                )

    return chunks
