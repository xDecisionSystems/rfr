from __future__ import annotations

from pathlib import Path

import fitz


def load_pdf(path: str) -> list[dict]:
    """Extract full text from each PDF page and attach page/source metadata."""
    source = Path(path).name
    pages: list[dict] = []

    with fitz.open(path) as doc:
        for page_number, page in enumerate(doc, start=1):
            pages.append(
                {
                    "source": source,
                    "file_path": str(Path(path).resolve()),
                    "page": page_number,
                    "text": page.get_text("text"),
                }
            )

    return pages
