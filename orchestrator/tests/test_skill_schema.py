"""Tests for skill schema validation and registry loading."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml
from pydantic import ValidationError

from orchestrator.skill_schema import (
    ModelRequirement,
    ModelSize,
    OutputFormat,
    ResourceBudget,
    SkillDefinition,
    _DEFAULT_MODEL,
    load_skill,
    load_skill_registry,
)

@pytest.fixture
def sample_skill_data() -> dict:
    return {
        "name": "code-review",
        "description": "Review code for quality, security, and best practices",
        "version": "1.0.0",
        "tags": ["code", "review", "quality"],
        "model": {
            "endpoint": "http://127.0.0.1:11434/v1",
            "model": "mlx-community/Qwen2.5-Coder-32B-Instruct-4bit",
            "size": "medium",
            "temperature": 0.3,
            "max_tokens": 8192,
            "json_mode": False,
        },
        "system_prompt": "You are an expert code reviewer.",
        "output_format": "markdown",
        "resources": {
            "max_memory_gb": 20.0,
            "max_duration_seconds": 120,
            "max_input_tokens": 32768,
        },
        "examples": [
            "Review this Python function for bugs",
            "Check this code for security issues",
        ],
    }


@pytest.fixture
def skill_yaml_dir(tmp_path: Path, sample_skill_data: dict) -> Path:
    skill_dir = tmp_path / "skills"
    skill_dir.mkdir()
    skill_file = skill_dir / "code-review.yaml"
    with skill_file.open("w") as f:
        yaml.dump(sample_skill_data, f)
    return skill_dir


class TestSkillDefinition:
    def test_minimal_skill(self):
        skill = SkillDefinition(
            name="test-skill",
            description="A test skill",
        )
        assert skill.name == "test-skill"
        assert skill.version == "1.0.0"
        assert skill.output_format == OutputFormat.TEXT
        assert skill.model.model == _DEFAULT_MODEL

    def test_full_skill(self, sample_skill_data: dict):
        skill = SkillDefinition.model_validate(sample_skill_data)
        assert skill.name == "code-review"
        assert skill.model.temperature == 0.3
        assert skill.model.size == ModelSize.MEDIUM
        assert skill.output_format == OutputFormat.MARKDOWN
        assert len(skill.examples) == 2

    def test_model_defaults(self):
        model = ModelRequirement()
        assert model.endpoint == "http://127.0.0.1:11434/v1"
        assert model.model == _DEFAULT_MODEL
        assert model.temperature == 0.7

    def test_resource_defaults(self):
        resources = ResourceBudget()
        assert resources.max_memory_gb == 20.0
        assert resources.max_duration_seconds == 300

    def test_temperature_validation(self):
        with pytest.raises(ValidationError):
            ModelRequirement(temperature=3.0)

    def test_max_tokens_validation(self):
        with pytest.raises(ValidationError):
            ModelRequirement(max_tokens=0)


class TestSystemPromptResolution:
    def test_inline_prompt(self):
        skill = SkillDefinition(
            name="test",
            description="test",
            system_prompt="You are helpful.",
        )
        assert skill.resolve_system_prompt(Path(".")) == "You are helpful."

    def test_file_prompt(self, tmp_path: Path):
        prompt_file = tmp_path / "prompt.md"
        prompt_file.write_text("You are an expert assistant.")
        skill = SkillDefinition(
            name="test",
            description="test",
            system_prompt_file="prompt.md",
        )
        assert skill.resolve_system_prompt(tmp_path) == "You are an expert assistant."

    def test_missing_file_prompt(self, tmp_path: Path):
        skill = SkillDefinition(
            name="test",
            description="test",
            system_prompt_file="nonexistent.md",
        )
        with pytest.raises(FileNotFoundError):
            skill.resolve_system_prompt(tmp_path)

    @patch("orchestrator.skill_schema.load_prompt_resource")
    def test_catalog_prompt(self, mock_load_prompt: MagicMock):
        mock_load_prompt.return_value = "Canonical prompt."
        skill = SkillDefinition(
            name="test",
            description="test",
            system_prompt_resource="prompt://dryvist/applications/test",
        )

        assert skill.resolve_system_prompt(Path(".")) == "Canonical prompt."
        mock_load_prompt.assert_called_once_with(
            "prompt://dryvist/applications/test",
        )


class TestLoadSkill:
    def test_load_from_yaml(self, skill_yaml_dir: Path):
        skill = load_skill(skill_yaml_dir / "code-review.yaml")
        assert skill.name == "code-review"
        assert skill.model.temperature == 0.3

    def test_load_invalid_yaml(self, tmp_path: Path):
        bad_file = tmp_path / "bad.yaml"
        bad_file.write_text("name: 123\n")
        with pytest.raises(ValidationError):
            load_skill(bad_file)


class TestLoadSkillRegistry:
    def test_load_directory(self, skill_yaml_dir: Path):
        registry = load_skill_registry(skill_yaml_dir)
        assert "code-review" in registry
        assert len(registry) == 1

    def test_missing_directory(self):
        with pytest.raises(FileNotFoundError):
            load_skill_registry(Path("/nonexistent"))

    def test_duplicate_names(self, skill_yaml_dir: Path):
        # Add a second file with the same skill name
        dup_data = {
            "name": "code-review",
            "description": "Duplicate",
        }
        dup_file = skill_yaml_dir / "code-review-dup.yaml"
        with dup_file.open("w") as f:
            yaml.dump(dup_data, f)
        with pytest.raises(ValueError, match="Duplicate skill name"):
            load_skill_registry(skill_yaml_dir)

    def test_ignores_non_yaml(self, skill_yaml_dir: Path):
        (skill_yaml_dir / "readme.md").write_text("# Not a skill")
        registry = load_skill_registry(skill_yaml_dir)
        assert len(registry) == 1

    def test_multiple_skills(self, skill_yaml_dir: Path):
        second_skill = {
            "name": "code-explain",
            "description": "Explain code in plain language",
            "tags": ["code", "explain"],
        }
        with (skill_yaml_dir / "code-explain.yaml").open("w") as f:
            yaml.dump(second_skill, f)
        registry = load_skill_registry(skill_yaml_dir)
        assert len(registry) == 2
        assert "code-explain" in registry
