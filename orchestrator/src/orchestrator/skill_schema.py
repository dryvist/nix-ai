"""Declarative skill schema and registry for local AI skill orchestration.

Defines Pydantic models for skill configuration loaded from YAML files.
Skills describe a task template with model requirements, prompts, tools,
and output schemas that the orchestrator uses to route and execute requests.
"""

from __future__ import annotations

import os
from enum import Enum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from orchestrator.common import load_yaml_file
from orchestrator.prompts import load_prompt_resource

_DEFAULT_MODEL = os.environ.get("MLX_DEFAULT_MODEL", "default")


class ModelSize(str, Enum):
    """Model size categories for resource planning."""

    SMALL = "small"  # 7-8B params, ~5GB VRAM
    MEDIUM = "medium"  # 27-35B params, ~15-20GB VRAM
    LARGE = "large"  # 70B+ params, ~40GB+ VRAM
    EMBEDDING = "embedding"  # Embedding models, ~300MB


class OutputFormat(str, Enum):
    """Supported output formats for skill results."""

    TEXT = "text"
    JSON = "json"
    MARKDOWN = "markdown"
    DIFF = "diff"


class ModelRequirement(BaseModel):
    """Specifies which model a skill needs and how to reach it."""

    endpoint: str = Field(
        default="http://127.0.0.1:11434/v1",
        description="OpenAI-compatible API endpoint URL",
    )
    model: str = Field(
        default=_DEFAULT_MODEL,
        description="Model identifier (HuggingFace ID for MLX models)",
    )
    size: ModelSize = Field(
        default=ModelSize.MEDIUM,
        description="Model size category for resource planning",
    )
    temperature: float = Field(
        default=0.7,
        ge=0.0,
        le=2.0,
        description="Sampling temperature",
    )
    max_tokens: int = Field(
        default=4096,
        gt=0,
        description="Maximum tokens in the response",
    )
    json_mode: bool = Field(
        default=False,
        description="Whether to request structured JSON output",
    )


class ToolDefinition(BaseModel):
    """A tool that can be invoked during skill execution."""

    name: str = Field(description="Tool name")
    description: str = Field(description="What the tool does")
    parameters: dict[str, Any] = Field(
        default_factory=dict,
        description="JSON Schema for tool parameters",
    )


class ResourceBudget(BaseModel):
    """Resource constraints for skill execution."""

    max_memory_gb: float = Field(
        default=20.0,
        description="Maximum GPU/unified memory in GB",
    )
    max_duration_seconds: int = Field(
        default=300,
        description="Maximum execution time in seconds",
    )
    max_input_tokens: int = Field(
        default=32768,
        description="Maximum input context tokens",
    )


class SkillDefinition(BaseModel):
    """Complete definition of a skill loaded from YAML.

    A skill is a repeatable task template that specifies:
    - What model to use (and how to configure it)
    - What system prompt to apply
    - What tools are available
    - What output format to expect
    - What resources it needs
    """

    model_config = ConfigDict(extra="forbid")

    name: str = Field(description="Unique skill identifier (kebab-case)")
    description: str = Field(description="Human-readable description of what the skill does")
    version: str = Field(default="1.0.0", description="Semantic version of the skill definition")
    tags: list[str] = Field(
        default_factory=list,
        description="Tags for categorization and routing",
    )

    model: ModelRequirement = Field(
        default_factory=ModelRequirement,
        description="Model configuration for this skill",
    )

    system_prompt: str = Field(
        default="",
        description="System prompt text (inline). Use system_prompt_file for file-based prompts",
    )
    system_prompt_file: str | None = Field(
        default=None,
        description="Path to external system prompt file (relative to skill YAML)",
    )
    system_prompt_resource: str | None = Field(
        default=None,
        description="Canonical prompt://dryvist resource provided by the Nix prompt catalog",
    )

    tools: list[ToolDefinition] = Field(
        default_factory=list,
        description="Tools available during skill execution",
    )

    output_format: OutputFormat = Field(
        default=OutputFormat.TEXT,
        description="Expected output format",
    )
    output_schema: dict[str, Any] | None = Field(
        default=None,
        description="JSON Schema for structured output (when output_format is JSON)",
    )

    resources: ResourceBudget = Field(
        default_factory=ResourceBudget,
        description="Resource constraints for this skill",
    )

    examples: list[str] = Field(
        default_factory=list,
        description="Example prompts that should route to this skill",
    )

    def resolve_system_prompt(self, base_dir: Path) -> str:
        """Resolve the system prompt, loading from file if specified."""
        if self.system_prompt_resource:
            return load_prompt_resource(self.system_prompt_resource)
        if self.system_prompt_file:
            prompt_path = base_dir / self.system_prompt_file
            if prompt_path.exists():
                return prompt_path.read_text()
            msg = f"System prompt file not found: {prompt_path}"
            raise FileNotFoundError(msg)
        return self.system_prompt


def load_skill(path: Path) -> SkillDefinition:
    """Load a single skill definition from a YAML file."""
    data = load_yaml_file(path)
    return SkillDefinition.model_validate(data)


def load_skill_registry(directory: Path) -> dict[str, SkillDefinition]:
    """Load all skill definitions from a directory of YAML files.

    Scans for *.yaml and *.yml files, validates each against the schema,
    and returns a dict keyed by skill name.
    """
    skills: dict[str, SkillDefinition] = {}
    if not directory.is_dir():
        msg = f"Skill registry directory not found: {directory}"
        raise FileNotFoundError(msg)

    for yaml_path in sorted(directory.iterdir()):
        if yaml_path.suffix not in {".yaml", ".yml"}:
            continue
        skill = load_skill(yaml_path)
        if skill.name in skills:
            msg = f"Duplicate skill name '{skill.name}' in {yaml_path}"
            raise ValueError(msg)
        skills[skill.name] = skill

    return skills
