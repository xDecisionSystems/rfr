from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from config.settings import settings
from ingestion.chunker import chunk_pages
from ingestion.pdf_loader import load_pdf
from services.embeddings import embed_texts
from services.vector_store import upsert


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest all PDFs in a folder into Qdrant")
    parser.add_argument(
        "folder",
        nargs="?",
        default=str(settings.default_papers_dir),
        help="Folder containing PDF files (default: data/papers)",
    )
    args = parser.parse_args()

    folder = Path(args.folder).expanduser().resolve()
    if not folder.exists() or not folder.is_dir():
        raise SystemExit(f"Invalid folder path: {folder}")

    pdf_paths = sorted(folder.rglob("*.pdf"))
    if not pdf_paths:
        raise SystemExit(f"No PDFs found in {folder}")

    all_chunks: list[dict] = []
    for pdf_path in pdf_paths:
        pages = load_pdf(str(pdf_path))
        chunks = chunk_pages(pages)
        all_chunks.extend(chunks)
        print(f"[ingest] {pdf_path.name}: pages={len(pages)} chunks={len(chunks)}")

    if not all_chunks:
        raise SystemExit("No chunks generated from provided PDFs.")

    embeddings = embed_texts([chunk["text"] for chunk in all_chunks])
    upserted = upsert(all_chunks, embeddings)

    print(f"[done] PDFs={len(pdf_paths)} chunks={len(all_chunks)} upserted={upserted}")


if __name__ == "__main__":
    main()
