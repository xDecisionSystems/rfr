from __future__ import annotations

from openai import AzureOpenAI

from config.settings import settings

_client = AzureOpenAI(
    azure_endpoint=settings.azure_openai_endpoint,
    api_key=settings.azure_openai_api_key,
    api_version=settings.azure_openai_api_version,
)


def embed_texts(texts: list[str]) -> list[list[float]]:
    """Generate embeddings via Azure OpenAI deployment."""
    if not texts:
        return []

    cleaned = [text.replace("\n", " ").strip() for text in texts]
    vectors: list[list[float]] = []

    for i in range(0, len(cleaned), settings.embedding_batch_size):
        batch = cleaned[i : i + settings.embedding_batch_size]
        response = _client.embeddings.create(
            model=settings.embedding_deployment_name,
            input=batch,
        )
        vectors.extend(item.embedding for item in sorted(response.data, key=lambda x: x.index))

    return vectors
