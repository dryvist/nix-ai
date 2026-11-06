"""Tests for the LangGraph Workflow Engine."""

from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
import yaml
from pydantic import ValidationError

from orchestrator.workflows.engine import (
    EdgeDefinition,
    NodeDefinition,
    NodeType,
    WorkflowDefinition,
    WorkflowEngine,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def simple_workflow_dict() -> dict[str, Any]:
    """Minimal valid two-node linear workflow."""
    return {
        "name": "test-workflow",
        "description": "A simple test workflow",
        "nodes": [
            {
                "name": "first",
                "type": "llm_call",
                "config": {
                    "model": "test-model",
                    "endpoint": "https://router.example.invalid/v1",
                    "system_prompt": "You are a test assistant.",
                },
                "description": "First node",
            },
            {
                "name": "second",
                "type": "tool_exec",
                "config": {"command": "echo", "args": ["done"]},
                "description": "Second node",
            },
        ],
        "edges": [{"source": "first", "target": "second"}],
        "entry_point": "first",
    }


@pytest.fixture
def conditional_workflow_dict() -> dict[str, Any]:
    """Workflow with a conditional routing node."""
    return {
        "name": "conditional-workflow",
        "description": "Workflow with conditional routing",
        "nodes": [
            {
                "name": "analyze",
                "type": "llm_call",
                "config": {
                    "model": "test-model",
                    "endpoint": "https://router.example.invalid/v1",
                    "system_prompt": "Analyze the input.",
                },
            },
            {
                "name": "check",
                "type": "conditional",
                "config": {
                    "condition_key": "has_issue",
                    "true_target": "flag",
                    "false_target": "approve",
                },
            },
            {
                "name": "flag",
                "type": "tool_exec",
                "config": {"command": "echo", "args": ["flagged"]},
            },
            {
                "name": "approve",
                "type": "tool_exec",
                "config": {"command": "echo", "args": ["approved"]},
            },
        ],
        "edges": [
            {"source": "analyze", "target": "check"},
        ],
        "entry_point": "analyze",
    }


@pytest.fixture
def single_node_workflow_dict() -> dict[str, Any]:
    """Workflow with a single node and no edges."""
    return {
        "name": "single-node",
        "description": "Single node workflow",
        "nodes": [
            {
                "name": "only",
                "type": "tool_exec",
                "config": {"command": "echo", "args": ["hello"]},
            },
        ],
        "edges": [],
        "entry_point": "only",
    }


@pytest.fixture
def workflow_yaml_file(tmp_path: Path, simple_workflow_dict: dict) -> Path:
    """Write the simple workflow dict to a temp YAML file."""
    yaml_file = tmp_path / "test-workflow.yaml"
    yaml_file.write_text(yaml.dump(simple_workflow_dict))
    return yaml_file


# ---------------------------------------------------------------------------
# NodeType enum tests
# ---------------------------------------------------------------------------


class TestNodeTypeEnum:
    def test_llm_call_value(self):
        assert NodeType.LLM_CALL == "llm_call"

    def test_tool_exec_value(self):
        assert NodeType.TOOL_EXEC == "tool_exec"

    def test_human_input_value(self):
        assert NodeType.HUMAN_INPUT == "human_input"

    def test_conditional_value(self):
        assert NodeType.CONDITIONAL == "conditional"

    def test_all_four_values(self):
        assert len(NodeType) == 4


# ---------------------------------------------------------------------------
# WorkflowDefinition validation tests
# ---------------------------------------------------------------------------


class TestWorkflowDefinitionValidation:
    def test_valid_workflow(self, simple_workflow_dict: dict):
        wf = WorkflowDefinition.model_validate(simple_workflow_dict)
        assert wf.name == "test-workflow"
        assert len(wf.nodes) == 2
        assert len(wf.edges) == 1
        assert wf.entry_point == "first"

    def test_missing_name_raises(self):
        data = {
            "description": "No name",
            "nodes": [{"name": "n", "type": "tool_exec"}],
            "entry_point": "n",
        }
        with pytest.raises(ValidationError):
            WorkflowDefinition.model_validate(data)

    def test_missing_entry_point_raises(self):
        data = {
            "name": "wf",
            "description": "desc",
            "nodes": [{"name": "n", "type": "tool_exec"}],
        }
        with pytest.raises(ValidationError):
            WorkflowDefinition.model_validate(data)

    def test_node_defaults(self):
        node = NodeDefinition(name="test", type=NodeType.TOOL_EXEC)
        assert node.config == {}
        assert node.description is None

    def test_edge_optional_condition(self):
        edge = EdgeDefinition(source="a", target="b")
        assert edge.condition is None

    def test_edge_with_condition(self):
        edge = EdgeDefinition(source="a", target="b", condition="state.flag == True")
        assert edge.condition == "state.flag == True"


# ---------------------------------------------------------------------------
# load_workflow / load_workflow_from_dict tests
# ---------------------------------------------------------------------------


class TestLoadWorkflow:
    def test_load_from_dict(self, simple_workflow_dict: dict):
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(simple_workflow_dict)
        assert isinstance(wf, WorkflowDefinition)
        assert wf.name == "test-workflow"

    def test_load_from_yaml_file(self, workflow_yaml_file: Path):
        engine = WorkflowEngine()
        wf = engine.load_workflow(workflow_yaml_file)
        assert isinstance(wf, WorkflowDefinition)
        assert wf.name == "test-workflow"

    def test_load_from_yaml_string_path(self, workflow_yaml_file: Path):
        engine = WorkflowEngine()
        wf = engine.load_workflow(str(workflow_yaml_file))
        assert wf.entry_point == "first"

    def test_load_missing_file_raises(self, tmp_path: Path):
        engine = WorkflowEngine()
        with pytest.raises(FileNotFoundError):
            engine.load_workflow(tmp_path / "nonexistent.yaml")

    def test_load_invalid_dict_raises(self):
        engine = WorkflowEngine()
        with pytest.raises(ValidationError):
            engine.load_workflow_from_dict({"name": 123})


# ---------------------------------------------------------------------------
# build_graph tests
# ---------------------------------------------------------------------------


class TestBuildGraph:
    def test_build_graph_returns_compiled(self, simple_workflow_dict: dict):
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(simple_workflow_dict)
        graph = engine.build_graph(wf)
        # A compiled LangGraph graph has an `invoke` method
        assert callable(getattr(graph, "invoke", None))

    def test_build_graph_invalid_entry_point(self, simple_workflow_dict: dict):
        simple_workflow_dict["entry_point"] = "does_not_exist"
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(simple_workflow_dict)
        with pytest.raises(ValueError, match="entry_point"):
            engine.build_graph(wf)

    def test_build_graph_single_node(self, single_node_workflow_dict: dict):
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(single_node_workflow_dict)
        graph = engine.build_graph(wf)
        assert callable(getattr(graph, "invoke", None))

    def test_build_graph_conditional_invalid_target(self, conditional_workflow_dict: dict):
        # Corrupt one of the conditional targets
        for node in conditional_workflow_dict["nodes"]:
            if node["name"] == "check":
                node["config"]["true_target"] = "ghost_node"
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(conditional_workflow_dict)
        with pytest.raises(ValueError, match="ghost_node"):
            engine.build_graph(wf)


# ---------------------------------------------------------------------------
# execute tests (mocked LLM + tool_exec)
# ---------------------------------------------------------------------------


def _make_fake_completion(content: str) -> MagicMock:
    """Build a minimal fake OpenAI ChatCompletion response."""
    msg = MagicMock()
    msg.content = content
    choice = MagicMock()
    choice.message = msg
    resp = MagicMock()
    resp.choices = [choice]
    return resp


class TestExecute:
    @patch("orchestrator.workflows.nodes.subprocess.run")
    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_execute_two_node_workflow(
        self,
        mock_openai_cls: MagicMock,
        mock_subprocess: MagicMock,
        simple_workflow_dict: dict,
    ):
        # Mock LLM response
        mock_client = MagicMock()
        mock_openai_cls.return_value = mock_client
        mock_client.chat.completions.create.return_value = _make_fake_completion(
            "LLM analysis result"
        )

        # Mock subprocess (tool_exec node)
        proc = MagicMock()
        proc.returncode = 0
        proc.stdout = "done"
        proc.stderr = ""
        mock_subprocess.return_value = proc

        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(simple_workflow_dict)
        result = engine.execute(wf, {"messages": [{"role": "user", "content": "hello"}]})

        assert isinstance(result, dict)
        # After tool_exec node, output should be the command stdout
        assert result.get("output") == "done"

    @patch("orchestrator.workflows.nodes.subprocess.run")
    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_execute_conditional_routing_true_branch(
        self,
        mock_openai_cls: MagicMock,
        mock_subprocess: MagicMock,
        conditional_workflow_dict: dict,
    ):
        mock_client = MagicMock()
        mock_openai_cls.return_value = mock_client
        mock_client.chat.completions.create.return_value = _make_fake_completion(
            "issues found"
        )

        proc = MagicMock()
        proc.returncode = 0
        proc.stdout = "flagged"
        proc.stderr = ""
        mock_subprocess.return_value = proc

        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(conditional_workflow_dict)
        # has_issue=True → should route to flag node
        result = engine.execute(
            wf,
            {"messages": [{"role": "user", "content": "review this"}], "metadata": {"has_issue": True}},
        )
        assert result.get("output") == "flagged"

    @patch("orchestrator.workflows.nodes.subprocess.run")
    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_execute_conditional_routing_false_branch(
        self,
        mock_openai_cls: MagicMock,
        mock_subprocess: MagicMock,
        conditional_workflow_dict: dict,
    ):
        mock_client = MagicMock()
        mock_openai_cls.return_value = mock_client
        mock_client.chat.completions.create.return_value = _make_fake_completion("ok")

        proc = MagicMock()
        proc.returncode = 0
        proc.stdout = "approved"
        proc.stderr = ""
        mock_subprocess.return_value = proc

        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(conditional_workflow_dict)
        # has_issue=False → should route to approve node
        result = engine.execute(
            wf,
            {"messages": [{"role": "user", "content": "review this"}], "metadata": {"has_issue": False}},
        )
        assert result.get("output") == "approved"

    def test_execute_human_input_node(self):
        workflow_dict = {
            "name": "human-wf",
            "description": "Workflow with human input",
            "nodes": [
                {
                    "name": "pause",
                    "type": "human_input",
                    "config": {"prompt": "Please review and approve."},
                },
            ],
            "edges": [],
            "entry_point": "pause",
        }
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(workflow_dict)
        result = engine.execute(wf, {"messages": []})
        assert result.get("pending_human_input") is True
        assert "Please review" in result.get("human_input_prompt", "")

    @patch("orchestrator.workflows.nodes.subprocess.run")
    def test_human_input_node_is_terminal_even_with_outgoing_edge(
        self,
        mock_subprocess: MagicMock,
    ):
        """human_input nodes must route to END regardless of outgoing edges in the YAML.

        This guards against the regression where the engine would wire an explicit
        outgoing edge from a human_input node, causing the graph to continue
        immediately instead of halting for human review.
        """
        proc = MagicMock()
        proc.returncode = 0
        proc.stdout = "should-not-appear"
        proc.stderr = ""
        mock_subprocess.return_value = proc

        workflow_dict = {
            "name": "human-terminal-wf",
            "description": "Verify human_input always routes to END",
            "nodes": [
                {
                    "name": "pause",
                    "type": "human_input",
                    "config": {"prompt": "Critical issues. Please approve."},
                },
                {
                    "name": "next_step",
                    "type": "tool_exec",
                    "config": {"command": "echo", "args": ["should-not-appear"]},
                },
            ],
            # Even though an outgoing edge is declared, the engine must ignore it
            # for human_input nodes and wire to END instead.
            "edges": [{"source": "pause", "target": "next_step"}],
            "entry_point": "pause",
        }
        engine = WorkflowEngine()
        wf = engine.load_workflow_from_dict(workflow_dict)
        result = engine.execute(wf, {"messages": []})

        # Graph must have halted at the human_input node
        assert result.get("pending_human_input") is True
        assert result.get("current_node") == "pause"
        # next_step must NOT have executed
        assert result.get("output") != "should-not-appear"


# ---------------------------------------------------------------------------
# Checkpointing configuration test
# ---------------------------------------------------------------------------


class TestCheckpointingConfiguration:
    def test_checkpointing_disabled_by_default(self):
        engine = WorkflowEngine()
        assert engine.checkpointing is False
        assert engine._checkpointer is None

    def test_checkpointing_enabled_in_memory(self):
        """Enable checkpointing with in-memory SQLite (no file I/O needed)."""
        try:
            from langgraph.checkpoint.sqlite import SqliteSaver  # noqa: F401

            engine = WorkflowEngine(checkpointing=True, db_path=":memory:")
            assert engine.checkpointing is True
            # _checkpointer may be None if SqliteSaver import fails in env
        except ImportError:
            pytest.skip("langgraph[sqlite] not available in this environment")
