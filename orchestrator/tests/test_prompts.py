"""Tests for loading OKF prompt resources from the Nix-injected catalog."""

from pathlib import Path

import pytest

from orchestrator.prompts import load_prompt_resource, strip_okf_frontmatter


def test_strip_okf_frontmatter() -> None:
    content = "---\ntype: LLM Prompt\nresource: prompt://dryvist/applications/test\n---\nPrompt body.\n"
    assert strip_okf_frontmatter(content) == "Prompt body."


def test_load_prompt_resource(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    prompt_path = tmp_path / "test-prompt.md"
    prompt_path.write_text("---\ntype: LLM Prompt\n---\nCanonical prompt.\n")
    monkeypatch.setenv("NIX_AI_PROMPT_DIR", str(tmp_path))

    result = load_prompt_resource("prompt://dryvist/applications/test-prompt")

    assert result == "Canonical prompt."


def test_load_prompt_resource_requires_nix_environment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NIX_AI_PROMPT_DIR", raising=False)
    with pytest.raises(RuntimeError, match="NIX_AI_PROMPT_DIR"):
        load_prompt_resource("prompt://dryvist/applications/test-prompt")


@pytest.mark.parametrize(
    "content",
    ["Prompt body without metadata", "---\n---\nPrompt body"],
)
def test_strip_okf_frontmatter_rejects_invalid_metadata(content: str) -> None:
    with pytest.raises(ValueError, match="OKF frontmatter"):
        strip_okf_frontmatter(content)
