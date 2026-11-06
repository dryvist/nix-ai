"""Embedding-based semantic skill router.

Routes incoming prompts to the best-matching skill using cosine similarity
on skill description embeddings. No LLM overhead for routing decisions —
uses a local embedding model (nomic-embed-text-v1.5 or similar) via an
OpenAI-compatible endpoint.

The router:
1. Embeds all registered skill descriptions + example prompts at init time
2. Embeds incoming user prompts at query time
3. Returns the best-matching skill via cosine similarity
4. Falls back gracefully when confidence is below threshold
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import numpy as np

from orchestrator.common import local_router_url, l2_normalize

if TYPE_CHECKING:
    from openai import OpenAI

    from .skill_schema import SkillDefinition

logger = logging.getLogger(__name__)


@dataclass
class RouteResult:
    """Result of routing a prompt to a skill."""

    skill_name: str
    score: float
    skill: SkillDefinition
    below_threshold: bool = False


@dataclass
class SkillRouter:
    """Embedding-based semantic skill router.

    Uses an OpenAI-compatible embedding endpoint to embed skill descriptions
    and match incoming prompts via cosine similarity.
    """

    embedding_endpoint: str = field(default_factory=local_router_url)
    embedding_model: str = "nomic-embed-text-v1.5"
    threshold: float = 0.3
    _skills: dict[str, SkillDefinition] = field(default_factory=dict)
    _embeddings: np.ndarray | None = field(default=None, repr=False)
    _skill_names: list[str] = field(default_factory=list)
    _client: OpenAI | None = field(default=None, repr=False)

    def _get_client(self):
        """Lazy-initialize the OpenAI client."""
        if self._client is None:
            from openai import OpenAI

            self._client = OpenAI(
                base_url=self.embedding_endpoint,
                api_key="not-needed",
            )
        return self._client

    def _embed(self, texts: list[str]) -> np.ndarray:
        """Generate embeddings for a list of texts."""
        client = self._get_client()
        response = client.embeddings.create(
            model=self.embedding_model,
            input=texts,
        )
        return np.array([item.embedding for item in response.data])

    def register_skills(self, skills: dict[str, SkillDefinition]) -> None:
        """Register skills and pre-compute their embeddings.

        Each skill is represented by its description plus any example prompts,
        concatenated into a single embedding text for richer matching.
        """
        self._skills = dict(skills)
        self._skill_names = []
        texts = []

        for name, skill in sorted(skills.items()):
            self._skill_names.append(name)
            # Combine description and examples for richer embedding
            parts = [skill.description]
            parts.extend(skill.examples)
            combined = " | ".join(parts)
            texts.append(combined)

        if texts:
            self._embeddings = self._embed(texts)
            logger.info("Embedded %d skills for routing", len(texts))
        else:
            self._embeddings = None
            logger.warning("No skills registered — router will return no matches")

    def route(self, prompt: str, top_k: int = 1) -> list[RouteResult]:
        """Route a prompt to the best-matching skill(s).

        Returns a list of RouteResult sorted by score (highest first).
        Results below the threshold are flagged but still returned.
        """
        if self._embeddings is None or len(self._skill_names) == 0:
            return []

        top_k = max(1, min(top_k, len(self._skill_names)))

        prompt_embedding = self._embed([prompt])
        scores = _cosine_similarity(prompt_embedding, self._embeddings)[0]

        # Get top-k indices sorted by score descending
        top_indices = np.argsort(scores)[::-1][:top_k]

        results = []
        for idx in top_indices:
            name = self._skill_names[idx]
            score = float(scores[idx])
            results.append(
                RouteResult(
                    skill_name=name,
                    score=score,
                    skill=self._skills[name],
                    below_threshold=score < self.threshold,
                )
            )

        return results

    def route_best(self, prompt: str) -> RouteResult | None:
        """Route a prompt to the single best-matching skill.

        Returns None if no skills are registered or best match is
        below the confidence threshold.
        """
        results = self.route(prompt, top_k=1)
        if not results:
            return None
        best = results[0]
        if best.below_threshold:
            logger.info(
                "Best match '%s' (%.3f) is below threshold %.3f",
                best.skill_name,
                best.score,
                self.threshold,
            )
            return None
        return best


def _cosine_similarity(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Cosine similarity between (m, d) and (n, d) → (m, n) matrix."""
    return l2_normalize(a) @ l2_normalize(b).T
