from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    azure_openai_endpoint: str
    azure_openai_api_key: str
    azure_openai_api_version: str
    embedding_deployment_name: str
    chat_deployment_name: str

    qdrant_host: str
    qdrant_port: int
    qdrant_collection: str

    default_top_k: int
    embedding_batch_size: int
    default_papers_dir: Path


def _required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def load_settings() -> Settings:
    return Settings(
        azure_openai_endpoint=_required("AZURE_OPENAI_ENDPOINT"),
        azure_openai_api_key=_required("AZURE_OPENAI_API_KEY"),
        azure_openai_api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-15-preview"),
        embedding_deployment_name=_required("EMBEDDING_DEPLOYMENT_NAME"),
        chat_deployment_name=_required("CHAT_DEPLOYMENT_NAME"),
        qdrant_host=os.getenv("QDRANT_HOST", "localhost"),
        qdrant_port=int(os.getenv("QDRANT_PORT", "6333")),
        qdrant_collection=os.getenv("QDRANT_COLLECTION", "research_papers"),
        default_top_k=int(os.getenv("DEFAULT_TOP_K", "5")),
        embedding_batch_size=int(os.getenv("EMBEDDING_BATCH_SIZE", "64")),
        default_papers_dir=BASE_DIR / "data" / "papers",
    )


settings = load_settings()
