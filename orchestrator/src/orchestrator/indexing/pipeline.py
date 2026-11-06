"""Embedding pipeline using llama-index IngestionPipeline.

Thin wrapper that handles:
1. Document ingestion with content-hash deduplication (SimpleDocumentStore)
2. Embedding via OpenAI-compatible endpoints (OpenAIEmbedding)
3. Vector storage in FAISS (default) or Qdrant (optional)
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import faiss
from pydantic import BaseModel, Field

from orchestrator.common import local_router_url

logger = logging.getLogger(__name__)

try:
    from llama_index.vector_stores.qdrant import QdrantVectorStore

    _QDRANT_AVAILABLE = True
except ImportError:
    _QDRANT_AVAILABLE = False


class EmbeddingConfig(BaseModel):
    """Configuration for the EmbeddingPipeline."""

    endpoint: str = Field(
        default_factory=local_router_url,
        description="OpenAI-compatible embedding endpoint from MLX_API_URL",
    )
    model: str = Field(
        default="nomic-embed-text",
        description="Embedding model identifier",
    )
    batch_size: int = Field(
        default=32,
        gt=0,
        description="Number of documents per embedding batch",
    )
    backend: str = Field(
        default="faiss",
        description="Vector backend to use: 'faiss' or 'qdrant'",
    )
    index_path: Path = Field(
        default=Path("./index"),
        description="File path prefix for persisting the index",
    )
    dimension: int = Field(
        default=384,
        gt=0,
        description="Embedding vector dimension (must match model output)",
    )


class EmbeddingPipeline:
    """High-level embedding pipeline backed by llama-index.

    Wraps IngestionPipeline with our EmbeddingConfig for a simple
    index/search/delete/save/load interface.
    """

    def __init__(self, config: EmbeddingConfig) -> None:
        from llama_index.core.ingestion import DocstoreStrategy, IngestionPipeline
        from llama_index.core.storage.docstore import SimpleDocumentStore
        from llama_index.embeddings.openai import OpenAIEmbedding
        from llama_index.vector_stores.faiss import FaissVectorStore

        self.config = config
        self._embed_model = OpenAIEmbedding(
            api_base=config.endpoint,
            api_key="not-needed",
            model_name=config.model,
        )
        self._vector_store = self._make_vector_store(config, FaissVectorStore)
        self._pipeline = IngestionPipeline(
            transformations=[self._embed_model],
            vector_store=self._vector_store,
            docstore=SimpleDocumentStore(),
            docstore_strategy=DocstoreStrategy.UPSERTS,
        )

    @staticmethod
    def _make_vector_store(config: EmbeddingConfig, faiss_vs_cls: type) -> Any:
        backend = config.backend.lower()
        if backend == "faiss":
            index = faiss.IndexFlatIP(config.dimension)
            return faiss_vs_cls(faiss_index=index)
        if backend == "qdrant":
            if not _QDRANT_AVAILABLE:
                msg = (
                    "qdrant-client is not installed. "
                    "Install with: pip install orchestrator[qdrant]"
                )
                raise ImportError(msg)
            return QdrantVectorStore(collection_name="orchestrator")
        msg = f"Unknown backend '{config.backend}'. Choose 'faiss' or 'qdrant'."
        raise ValueError(msg)

    def index(self, documents: list[dict[str, Any]]) -> None:
        """Embed and store documents. Unchanged content is skipped via docstore."""
        if not documents:
            return
        from llama_index.core.schema import Document

        docs = [
            Document(text=d["text"], metadata=d.get("metadata", {}), id_=d["id"])
            for d in documents
        ]
        self._pipeline.run(documents=docs)
        logger.info("EmbeddingPipeline: indexed %d documents", len(documents))

    def search(self, query: str, top_k: int = 5) -> list[dict[str, Any]]:
        """Embed query and return the top-k nearest documents."""
        from llama_index.core.vector_stores.types import VectorStoreQuery

        query_emb = self._embed_model.get_query_embedding(query)
        result = self._vector_store.query(
            VectorStoreQuery(query_embedding=query_emb, similarity_top_k=top_k)
        )
        nodes = result.nodes or []
        similarities = result.similarities or []
        return [
            {"id": node.id_, "score": float(score), "metadata": node.metadata}
            for node, score in zip(nodes, similarities)
        ]

    def delete(self, ids: list[str]) -> None:
        """Remove documents from the index by id."""
        for doc_id in ids:
            self._vector_store.delete(doc_id)

    def save(self, path: str | Path | None = None) -> None:
        """Persist the index to disk. Only supported for the 'faiss' backend."""
        if self.config.backend.lower() != "faiss":
            msg = f"save/load is not supported for the '{self.config.backend}' backend"
            raise NotImplementedError(msg)
        target = str(Path(path) if path is not None else self.config.index_path)
        self._vector_store.persist(persist_path=target)
        if self._pipeline.docstore is not None:
            self._pipeline.docstore.persist(persist_path=target)
        logger.info("EmbeddingPipeline: saved index to %s", target)

    def load(self, path: str | Path | None = None) -> None:
        """Load a previously saved index from disk. Only supported for the 'faiss' backend."""
        if self.config.backend.lower() != "faiss":
            msg = f"save/load is not supported for the '{self.config.backend}' backend"
            raise NotImplementedError(msg)
        from llama_index.core.ingestion import DocstoreStrategy, IngestionPipeline
        from llama_index.core.storage.docstore import SimpleDocumentStore
        from llama_index.vector_stores.faiss import FaissVectorStore

        target = str(Path(path) if path is not None else self.config.index_path)
        self._vector_store = FaissVectorStore.from_persist_dir(target)
        docstore = SimpleDocumentStore.from_persist_dir(target)
        self._pipeline = IngestionPipeline(
            transformations=[self._embed_model],
            vector_store=self._vector_store,
            docstore=docstore,
            docstore_strategy=DocstoreStrategy.UPSERTS,
        )
        logger.info("EmbeddingPipeline: loaded index from %s", target)
