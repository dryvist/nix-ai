"""Tests for the embedding pipeline wrapper around llama-index.

All llama-index components are mocked via sys.modules patching
so tests run without requiring llama-index or a live embedding server.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from orchestrator.indexing.pipeline import EmbeddingConfig


# ---------------------------------------------------------------------------
# Helpers for mocking llama-index
# ---------------------------------------------------------------------------

DIM = 8


def _make_mock_modules() -> dict[str, MagicMock]:
    """Build a sys.modules patch dict that mocks all llama-index packages."""
    # IngestionPipeline and DocstoreStrategy
    mock_ingestion = MagicMock()
    mock_ingestion.DocstoreStrategy = MagicMock()
    mock_ingestion.DocstoreStrategy.UPSERTS = "upserts"
    mock_ingestion.IngestionPipeline = MagicMock

    # SimpleDocumentStore
    mock_docstore_mod = MagicMock()
    mock_docstore_mod.SimpleDocumentStore = MagicMock()

    # OpenAIEmbedding
    mock_embed_mod = MagicMock()
    mock_embed_mod.OpenAIEmbedding = MagicMock

    # FaissVectorStore
    mock_faiss_mod = MagicMock()
    mock_faiss_vs = MagicMock()
    mock_faiss_mod.FaissVectorStore = mock_faiss_vs

    # Document
    mock_schema = MagicMock()
    mock_schema.Document = MagicMock

    # VectorStoreQuery
    mock_vs_types = MagicMock()
    mock_vs_types.VectorStoreQuery = MagicMock

    return {
        "llama_index": MagicMock(),
        "llama_index.core": MagicMock(),
        "llama_index.core.ingestion": mock_ingestion,
        "llama_index.core.storage": MagicMock(),
        "llama_index.core.storage.docstore": mock_docstore_mod,
        "llama_index.core.schema": mock_schema,
        "llama_index.core.vector_stores": MagicMock(),
        "llama_index.core.vector_stores.types": mock_vs_types,
        "llama_index.embeddings": MagicMock(),
        "llama_index.embeddings.openai": mock_embed_mod,
        "llama_index.vector_stores": MagicMock(),
        "llama_index.vector_stores.faiss": mock_faiss_mod,
    }


@pytest.fixture
def mock_li():
    """Patch sys.modules with mocked llama-index packages."""
    mocks = _make_mock_modules()
    with patch.dict("sys.modules", mocks):
        yield mocks


def _make_config(**kwargs: Any) -> EmbeddingConfig:
    defaults: dict[str, Any] = {"dimension": DIM, "batch_size": 4, "backend": "faiss"}
    defaults.update(kwargs)
    return EmbeddingConfig(**defaults)


def _make_docs(n: int, prefix: str = "doc") -> list[dict[str, Any]]:
    return [
        {
            "id": f"{prefix}{i}",
            "text": f"content for {prefix} {i}",
            "metadata": {"idx": i},
        }
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# EmbeddingConfig tests
# ---------------------------------------------------------------------------


class TestEmbeddingConfig:
    def test_defaults(self):
        cfg = EmbeddingConfig()
        assert cfg.endpoint == "https://router.example.invalid/v1"
        assert cfg.model == "nomic-embed-text"
        assert cfg.batch_size == 32
        assert cfg.backend == "faiss"
        assert cfg.index_path == Path("./index")
        assert cfg.dimension == 384

    def test_custom_values(self):
        cfg = EmbeddingConfig(
            endpoint="http://myhost:8080/v1",
            model="all-minilm",
            batch_size=16,
            backend="qdrant",
            index_path=Path("/tmp/myindex"),
            dimension=768,
        )
        assert cfg.endpoint == "http://myhost:8080/v1"
        assert cfg.model == "all-minilm"
        assert cfg.batch_size == 16
        assert cfg.backend == "qdrant"
        assert cfg.index_path == Path("/tmp/myindex")
        assert cfg.dimension == 768

    def test_batch_size_must_be_positive(self):
        with pytest.raises(Exception):
            EmbeddingConfig(batch_size=0)

    def test_dimension_must_be_positive(self):
        with pytest.raises(Exception):
            EmbeddingConfig(dimension=0)


# ---------------------------------------------------------------------------
# EmbeddingPipeline construction
# ---------------------------------------------------------------------------


class TestEmbeddingPipelineInit:
    def test_creates_pipeline_with_faiss(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)
        assert pipeline.config == config
        assert pipeline._embed_model is not None
        assert pipeline._vector_store is not None
        assert pipeline._pipeline is not None

    def test_unknown_backend_raises(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(backend="nonexistent")
        with pytest.raises(ValueError, match="Unknown backend"):
            EmbeddingPipeline(config)

    def test_qdrant_backend_raises_when_not_available(self, mock_li: dict):
        import orchestrator.indexing.pipeline as pipeline_mod

        original = pipeline_mod._QDRANT_AVAILABLE
        try:
            pipeline_mod._QDRANT_AVAILABLE = False
            from orchestrator.indexing.pipeline import EmbeddingPipeline

            config = _make_config(backend="qdrant")
            with pytest.raises(ImportError, match="qdrant-client"):
                EmbeddingPipeline(config)
        finally:
            pipeline_mod._QDRANT_AVAILABLE = original


# ---------------------------------------------------------------------------
# EmbeddingPipeline.index
# ---------------------------------------------------------------------------


class TestEmbeddingPipelineIndex:
    def test_index_calls_pipeline_run(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)
        pipeline._pipeline = MagicMock()
        docs = _make_docs(3)

        pipeline.index(docs)

        pipeline._pipeline.run.assert_called_once()
        call_args = pipeline._pipeline.run.call_args
        assert (
            len(
                call_args.kwargs.get(
                    "documents", call_args.args[0] if call_args.args else []
                )
            )
            == 3
        )

    def test_empty_document_list_is_noop(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)
        pipeline._pipeline = MagicMock()

        pipeline.index([])

        pipeline._pipeline.run.assert_not_called()


# ---------------------------------------------------------------------------
# EmbeddingPipeline.search
# ---------------------------------------------------------------------------


class TestEmbeddingPipelineSearch:
    def test_search_returns_formatted_results(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)

        # Mock embed model and vector store
        pipeline._embed_model = MagicMock()
        pipeline._embed_model.get_query_embedding.return_value = [0.1] * DIM

        node0 = MagicMock()
        node0.id_ = "doc0"
        node0.metadata = {"source": "a.md"}
        node1 = MagicMock()
        node1.id_ = "doc1"
        node1.metadata = {"source": "b.md"}

        mock_result = MagicMock()
        mock_result.nodes = [node0, node1]
        mock_result.similarities = [0.95, 0.80]
        pipeline._vector_store = MagicMock()
        pipeline._vector_store.query.return_value = mock_result

        results = pipeline.search("test query", top_k=2)

        assert len(results) == 2
        assert results[0] == {
            "id": "doc0",
            "score": 0.95,
            "metadata": {"source": "a.md"},
        }
        assert results[1] == {
            "id": "doc1",
            "score": 0.80,
            "metadata": {"source": "b.md"},
        }

    def test_search_handles_empty_results(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)

        pipeline._embed_model = MagicMock()
        pipeline._embed_model.get_query_embedding.return_value = [0.1] * DIM

        mock_result = MagicMock()
        mock_result.nodes = None
        mock_result.similarities = None
        pipeline._vector_store = MagicMock()
        pipeline._vector_store.query.return_value = mock_result

        results = pipeline.search("query")
        assert results == []


# ---------------------------------------------------------------------------
# EmbeddingPipeline.delete
# ---------------------------------------------------------------------------


class TestEmbeddingPipelineDelete:
    def test_delete_calls_vector_store(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)
        pipeline._vector_store = MagicMock()

        pipeline.delete(["doc0", "doc1"])

        assert pipeline._vector_store.delete.call_count == 2
        pipeline._vector_store.delete.assert_any_call("doc0")
        pipeline._vector_store.delete.assert_any_call("doc1")


# ---------------------------------------------------------------------------
# EmbeddingPipeline.save / load
# ---------------------------------------------------------------------------


class TestEmbeddingPipelineSaveLoad:
    def test_save_calls_persist(self, mock_li: dict, tmp_path: Path):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(index_path=tmp_path / "test_index")
        pipeline = EmbeddingPipeline(config)
        pipeline._vector_store = MagicMock()
        mock_docstore = MagicMock()
        pipeline._pipeline = MagicMock()
        pipeline._pipeline.docstore = mock_docstore

        pipeline.save()

        pipeline._vector_store.persist.assert_called_once()
        mock_docstore.persist.assert_called_once()

    def test_save_with_custom_path(self, mock_li: dict, tmp_path: Path):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config()
        pipeline = EmbeddingPipeline(config)
        pipeline._vector_store = MagicMock()
        pipeline._pipeline = MagicMock()
        pipeline._pipeline.docstore = MagicMock()

        custom_path = tmp_path / "custom_index"
        pipeline.save(custom_path)

        call_args = pipeline._vector_store.persist.call_args
        assert str(custom_path) in str(call_args)

    def test_save_skips_docstore_persist_when_none(self, mock_li: dict, tmp_path: Path):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(index_path=tmp_path / "test_index")
        pipeline = EmbeddingPipeline(config)
        pipeline._vector_store = MagicMock()
        pipeline._pipeline = MagicMock()
        pipeline._pipeline.docstore = None

        # Should not raise even when docstore is None
        pipeline.save()
        pipeline._vector_store.persist.assert_called_once()

    def test_load_replaces_vector_store_and_rebuilds_pipeline(
        self, mock_li: dict, tmp_path: Path
    ):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(index_path=tmp_path / "test_index")
        pipeline = EmbeddingPipeline(config)
        old_store = pipeline._vector_store
        old_pipeline = pipeline._pipeline

        # Mock FaissVectorStore.from_persist_dir
        mock_faiss_mod = mock_li["llama_index.vector_stores.faiss"]
        mock_new_store = MagicMock()
        mock_faiss_mod.FaissVectorStore.from_persist_dir.return_value = mock_new_store

        # Mock SimpleDocumentStore.from_persist_dir
        mock_docstore_mod = mock_li["llama_index.core.storage.docstore"]
        mock_docstore_mod.SimpleDocumentStore.from_persist_dir.return_value = MagicMock()

        pipeline.load()

        assert pipeline._vector_store is mock_new_store
        assert pipeline._vector_store is not old_store
        # Pipeline must be rebuilt so index() writes to the loaded store
        assert pipeline._pipeline is not old_pipeline

    def test_save_raises_for_qdrant_backend(self, mock_li: dict):
        import orchestrator.indexing.pipeline as pipeline_mod

        original = pipeline_mod._QDRANT_AVAILABLE
        try:
            pipeline_mod._QDRANT_AVAILABLE = True
            from orchestrator.indexing.pipeline import EmbeddingPipeline

            config = _make_config(backend="faiss")  # start faiss, then mutate
            pipeline = EmbeddingPipeline(config)
            # Simulate a pipeline that was configured with qdrant
            pipeline.config = _make_config(backend="qdrant")

            with pytest.raises(NotImplementedError, match="qdrant"):
                pipeline.save()
        finally:
            pipeline_mod._QDRANT_AVAILABLE = original

    def test_load_raises_for_qdrant_backend(self, mock_li: dict):
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(backend="faiss")
        pipeline = EmbeddingPipeline(config)
        pipeline.config = _make_config(backend="qdrant")

        with pytest.raises(NotImplementedError, match="qdrant"):
            pipeline.load()

    def test_save_load_case_insensitive_backend(self, mock_li: dict, tmp_path: Path):
        """Backend check must be case-insensitive to match _make_vector_store behavior."""
        from orchestrator.indexing.pipeline import EmbeddingPipeline

        config = _make_config(index_path=tmp_path / "case_index")
        pipeline = EmbeddingPipeline(config)
        pipeline._vector_store = MagicMock()
        pipeline._pipeline = MagicMock()
        pipeline._pipeline.docstore = MagicMock()
        # Mutate to title-case to verify .lower() normalization
        pipeline.config = _make_config(
            backend="Faiss", index_path=tmp_path / "case_index"
        )

        # save() must not raise NotImplementedError for "Faiss"
        pipeline.save()
        pipeline._vector_store.persist.assert_called_once()

        mock_faiss_mod = mock_li["llama_index.vector_stores.faiss"]
        mock_faiss_mod.FaissVectorStore.from_persist_dir.return_value = MagicMock()
        mock_docstore_mod = mock_li["llama_index.core.storage.docstore"]
        mock_docstore_mod.SimpleDocumentStore.from_persist_dir.return_value = MagicMock()

        # load() must not raise NotImplementedError for "Faiss"
        pipeline.load()
