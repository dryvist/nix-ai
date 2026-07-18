"""Tests for orchestrator.workflows.nodes — all factories tested in isolation."""

from __future__ import annotations

import subprocess
from unittest.mock import MagicMock, patch

from orchestrator.workflows.models import NodeDefinition, NodeType, WorkflowState
from orchestrator.workflows.nodes import (
    NODE_FACTORIES,
    _error_state,
    _make_human_input_node,
    _make_llm_call_node,
    _make_passthrough_node,
    _make_tool_exec_node,
)


# ---------------------------------------------------------------------------
# TestErrorState
# ---------------------------------------------------------------------------


class TestErrorState:
    """Tests for _error_state() helper."""

    def test_basic_fields(self) -> None:
        state: WorkflowState = {"current_node": "old", "messages": []}
        result = _error_state(state, "node1", "boom", 1, "runtime_error")
        assert result["current_node"] == "node1"
        assert result["output"] == "boom"
        assert result["metadata"]["node1_returncode"] == 1
        assert result["metadata"]["node1_error"] == "runtime_error"

    def test_preserves_existing_metadata(self) -> None:
        state: WorkflowState = {"current_node": "old", "metadata": {"prior": "data"}}
        result = _error_state(state, "n", "err", 2, "fail")
        assert result["metadata"]["prior"] == "data"
        assert result["metadata"]["n_returncode"] == 2

    def test_handles_empty_state(self) -> None:
        state: WorkflowState = {}
        result = _error_state(state, "x", "msg", 0, "none")
        assert result["metadata"]["x_returncode"] == 0


# ---------------------------------------------------------------------------
# TestMakePassthroughNode
# ---------------------------------------------------------------------------


class TestMakePassthroughNode:
    """Tests for _make_passthrough_node()."""

    def test_updates_current_node(self) -> None:
        node_def = NodeDefinition(name="router", type=NodeType.CONDITIONAL)
        fn = _make_passthrough_node(node_def)
        state: WorkflowState = {"current_node": "prev", "output": "keep"}
        result = fn(state)
        assert result["current_node"] == "router"

    def test_preserves_other_state(self) -> None:
        node_def = NodeDefinition(name="pass", type=NodeType.CONDITIONAL)
        fn = _make_passthrough_node(node_def)
        state: WorkflowState = {"messages": [{"role": "user", "content": "hi"}], "output": "val"}
        result = fn(state)
        assert result["messages"] == [{"role": "user", "content": "hi"}]
        assert result["output"] == "val"


# ---------------------------------------------------------------------------
# TestMakeLlmCallNode
# ---------------------------------------------------------------------------


class TestMakeLlmCallNode:
    """Tests for _make_llm_call_node()."""

    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_client_created_at_factory_time(self, mock_openai_cls: MagicMock) -> None:
        node_def = NodeDefinition(
            name="llm", type=NodeType.LLM_CALL,
            config={
                "endpoint": "http://localhost:1234/v1",
                "model": "test-model",
                "system_prompt": "Test prompt.",
            },
        )
        _make_llm_call_node(node_def)
        mock_openai_cls.assert_called_once_with(
            base_url="http://localhost:1234/v1", api_key="not-needed",
        )

    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_message_building(self, mock_openai_cls: MagicMock) -> None:
        mock_client = MagicMock()
        mock_openai_cls.return_value = mock_client
        mock_choice = MagicMock()
        mock_choice.message.content = "reply"
        mock_client.chat.completions.create.return_value = MagicMock(choices=[mock_choice])

        node_def = NodeDefinition(
            name="llm", type=NodeType.LLM_CALL,
            config={"system_prompt": "Be helpful."},
        )
        fn = _make_llm_call_node(node_def)
        state: WorkflowState = {"messages": [{"role": "user", "content": "hello"}]}
        fn(state)

        call_args = mock_client.chat.completions.create.call_args
        messages = call_args.kwargs["messages"]
        assert messages[0] == {"role": "system", "content": "Be helpful."}
        assert messages[1] == {"role": "user", "content": "hello"}

    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_response_extraction(self, mock_openai_cls: MagicMock) -> None:
        mock_client = MagicMock()
        mock_openai_cls.return_value = mock_client
        mock_choice = MagicMock()
        mock_choice.message.content = "the answer"
        mock_client.chat.completions.create.return_value = MagicMock(choices=[mock_choice])

        node_def = NodeDefinition(
            name="llm",
            type=NodeType.LLM_CALL,
            config={"system_prompt": "Test prompt."},
        )
        fn = _make_llm_call_node(node_def)
        result = fn({"messages": []})
        assert result["output"] == "the answer"
        assert result["messages"][-1]["content"] == "the answer"

    @patch("orchestrator.workflows.nodes.load_prompt_resource")
    @patch("orchestrator.workflows.nodes.OpenAI")
    def test_default_prompt_uses_catalog(
        self,
        mock_openai_cls: MagicMock,
        mock_load_prompt: MagicMock,
    ) -> None:
        mock_load_prompt.return_value = "Canonical default."
        node_def = NodeDefinition(name="llm", type=NodeType.LLM_CALL)

        _make_llm_call_node(node_def)

        mock_load_prompt.assert_called_once_with(
            "prompt://dryvist/applications/nix-ai-default-system",
        )
        mock_openai_cls.assert_called_once()


# ---------------------------------------------------------------------------
# TestMakeToolExecNode
# ---------------------------------------------------------------------------


class TestMakeToolExecNode:
    """Tests for _make_tool_exec_node()."""

    @patch("orchestrator.workflows.nodes.subprocess.run")
    def test_success(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0, stdout="hello\n", stderr="")
        node_def = NodeDefinition(
            name="echo", type=NodeType.TOOL_EXEC,
            config={"command": "echo", "args": ["hello"]},
        )
        fn = _make_tool_exec_node(node_def)
        result = fn({"messages": []})
        assert result["output"] == "hello"
        assert result["metadata"]["echo_returncode"] == 0

    @patch("orchestrator.workflows.nodes.subprocess.run")
    def test_failure_returns_stderr(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=1, stdout="out", stderr="err")
        node_def = NodeDefinition(
            name="fail", type=NodeType.TOOL_EXEC,
            config={"command": "false"},
        )
        fn = _make_tool_exec_node(node_def)
        result = fn({})
        assert result["output"] == "err"
        assert result["metadata"]["fail_returncode"] == 1

    @patch("orchestrator.workflows.nodes.subprocess.run")
    def test_file_not_found_returns_127(self, mock_run: MagicMock) -> None:
        mock_run.side_effect = FileNotFoundError()
        node_def = NodeDefinition(
            name="bad", type=NodeType.TOOL_EXEC,
            config={"command": "nosuchcmd"},
        )
        fn = _make_tool_exec_node(node_def)
        result = fn({})
        assert result["metadata"]["bad_returncode"] == 127
        assert result["metadata"]["bad_error"] == "command_not_found"

    @patch("orchestrator.workflows.nodes.subprocess.run")
    def test_timeout_returns_minus_1(self, mock_run: MagicMock) -> None:
        mock_run.side_effect = subprocess.TimeoutExpired(cmd="sleep", timeout=30)
        node_def = NodeDefinition(
            name="slow", type=NodeType.TOOL_EXEC,
            config={"command": "sleep", "args": ["999"], "timeout": 30},
        )
        fn = _make_tool_exec_node(node_def)
        result = fn({})
        assert result["metadata"]["slow_returncode"] == -1
        assert result["metadata"]["slow_error"] == "timeout"


# ---------------------------------------------------------------------------
# TestMakeHumanInputNode
# ---------------------------------------------------------------------------


class TestMakeHumanInputNode:
    """Tests for _make_human_input_node()."""

    def test_sets_pending_human_input(self) -> None:
        node_def = NodeDefinition(name="review", type=NodeType.HUMAN_INPUT)
        fn = _make_human_input_node(node_def)
        result = fn({"messages": []})
        assert result["pending_human_input"] is True

    def test_custom_vs_default_prompt(self) -> None:
        default_node = NodeDefinition(name="r1", type=NodeType.HUMAN_INPUT)
        custom_node = NodeDefinition(
            name="r2", type=NodeType.HUMAN_INPUT,
            config={"prompt": "Please approve."},
        )
        default_result = _make_human_input_node(default_node)({})
        custom_result = _make_human_input_node(custom_node)({})
        assert "Human review required" in default_result["human_input_prompt"]
        assert custom_result["human_input_prompt"] == "Please approve."


# ---------------------------------------------------------------------------
# TestNodeFactories
# ---------------------------------------------------------------------------


class TestNodeFactories:
    """Tests for the NODE_FACTORIES registry."""

    def test_all_node_types_present(self) -> None:
        for nt in NodeType:
            assert nt in NODE_FACTORIES, f"Missing factory for {nt}"
        assert len(NODE_FACTORIES) == len(NodeType)
