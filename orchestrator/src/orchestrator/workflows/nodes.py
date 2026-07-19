"""Node function factories for workflow graph execution.

Each factory accepts a NodeDefinition and returns a callable
(WorkflowState -> WorkflowState) suitable for use as a LangGraph node.

Node types:
  - llm_call: Invoke an OpenAI-compatible LLM endpoint
  - tool_exec: Execute a configured shell command/tool.
    **Warning**: This can execute arbitrary code and should only be used
    with trusted workflow definitions.
  - human_input: Pause execution and record pending human review
  - conditional: Route to different nodes based on state values (passthrough)
"""

from __future__ import annotations

import logging
import subprocess
from typing import Any, Callable

from openai import OpenAI

from orchestrator.prompts import load_prompt_resource
from orchestrator.workflows.models import NodeDefinition, NodeType, WorkflowState

logger = logging.getLogger(__name__)

DEFAULT_SYSTEM_PROMPT_RESOURCE = "prompt://dryvist/applications/nix-ai-default-system"


def _error_state(
    state: WorkflowState, node_name: str, msg: str, returncode: int, error_type: str
) -> WorkflowState:
    """Build a state dict for a node error."""
    return {
        **state,
        "current_node": node_name,
        "output": msg,
        "metadata": {
            **state.get("metadata", {}),
            f"{node_name}_returncode": returncode,
            f"{node_name}_error": error_type,
        },
    }


def _make_passthrough_node(
    node_def: NodeDefinition,
) -> Callable[[WorkflowState], WorkflowState]:
    """Return a no-op node function used as a routing placeholder."""

    def _node(state: WorkflowState) -> WorkflowState:
        return {**state, "current_node": node_def.name}

    _node.__name__ = node_def.name
    return _node


def _make_llm_call_node(
    node_def: NodeDefinition,
) -> Callable[[WorkflowState], WorkflowState]:
    """Return a node function that calls an OpenAI-compatible LLM endpoint."""
    cfg = node_def.config
    endpoint = cfg.get("endpoint", "http://127.0.0.1:11434/v1")
    model = cfg.get("model", "mlx-community/Qwen3.5-35B-A3B-4bit")
    system_prompt = cfg.get("system_prompt")
    if system_prompt is None:
        prompt_resource = cfg.get(
            "system_prompt_resource", DEFAULT_SYSTEM_PROMPT_RESOURCE,
        )
        system_prompt = load_prompt_resource(prompt_resource)
    temperature = float(cfg.get("temperature", 0.7))
    max_tokens = int(cfg.get("max_tokens", 4096))

    # Create client once at factory time instead of per-invocation
    client = OpenAI(base_url=endpoint, api_key="not-needed")

    def _node(state: WorkflowState) -> WorkflowState:
        messages: list[dict[str, str]] = [{"role": "system", "content": system_prompt}]
        messages.extend(state.get("messages", []))

        logger.debug("llm_call node '%s' → %s/%s", node_def.name, endpoint, model)
        response = client.chat.completions.create(
            model=model,
            messages=messages,  # type: ignore[arg-type]
            temperature=temperature,
            max_tokens=max_tokens,
        )
        reply = response.choices[0].message.content or ""

        updated_messages = list(state.get("messages", []))
        updated_messages.append({"role": "assistant", "content": reply})

        return {
            **state,
            "messages": updated_messages,
            "current_node": node_def.name,
            "output": reply,
        }

    _node.__name__ = node_def.name
    return _node


def _make_tool_exec_node(
    node_def: NodeDefinition,
) -> Callable[[WorkflowState], WorkflowState]:
    """Return a node function that executes a configured shell command."""
    cfg = node_def.config
    command = cfg.get("command", "echo")
    args = [str(a) for a in cfg.get("args", [])]
    timeout = int(cfg.get("timeout", 30))

    def _node(state: WorkflowState) -> WorkflowState:
        cmd = [command, *args]
        logger.debug("tool_exec node '%s' → %s", node_def.name, cmd)
        try:
            result = subprocess.run(  # noqa: S603
                cmd, capture_output=True, text=True, timeout=timeout,
            )
        except FileNotFoundError:
            return _error_state(
                state, node_def.name,
                f"tool_exec '{node_def.name}': command not found: {command}",
                127, "command_not_found",
            )
        except subprocess.TimeoutExpired:
            return _error_state(
                state, node_def.name,
                f"tool_exec '{node_def.name}': timed out after {timeout}s",
                -1, "timeout",
            )
        output = result.stdout.strip() if result.returncode == 0 else result.stderr.strip()
        return {
            **state,
            "current_node": node_def.name,
            "output": output,
            "metadata": {
                **state.get("metadata", {}),
                f"{node_def.name}_returncode": result.returncode,
            },
        }

    _node.__name__ = node_def.name
    return _node


def _make_human_input_node(
    node_def: NodeDefinition,
) -> Callable[[WorkflowState], WorkflowState]:
    """Return a node that records a pending human-input request."""
    prompt = node_def.config.get("prompt", "Human review required. Please provide input.")

    def _node(state: WorkflowState) -> WorkflowState:
        logger.info("human_input node '%s': %s", node_def.name, prompt)
        return {
            **state,
            "current_node": node_def.name,
            "pending_human_input": True,
            "human_input_prompt": prompt,
        }

    _node.__name__ = node_def.name
    return _node


NODE_FACTORIES: dict[NodeType, Callable[[NodeDefinition], Any]] = {
    NodeType.LLM_CALL: _make_llm_call_node,
    NodeType.TOOL_EXEC: _make_tool_exec_node,
    NodeType.HUMAN_INPUT: _make_human_input_node,
    NodeType.CONDITIONAL: _make_passthrough_node,
}
