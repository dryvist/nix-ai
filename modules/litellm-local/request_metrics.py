"""Emit one structured JSON event for each completed LiteLLM request.

The event contains request metadata only. It never records prompt or response
content.
"""

import json
from urllib.parse import urlparse

from litellm.integrations.custom_logger import CustomLogger


def _host_only(api_base):
    if not api_base:
        return None
    return urlparse(api_base).hostname or api_base


def build_record(kwargs, response_obj, start_time, end_time):
    """Build the normalized request event used by the proxy callback."""
    payload = kwargs.get("standard_logging_object") or {}
    metadata = payload.get("metadata") or {}
    error_info = payload.get("error_information") or {}

    start = payload.get("startTime")
    end = payload.get("endTime")
    latency_ms = (
        (end - start) * 1000
        if isinstance(start, (int, float)) and isinstance(end, (int, float))
        else None
    )
    completion_start = payload.get("completionStartTime")
    ttft_ms = (
        (completion_start - start) * 1000
        if isinstance(completion_start, (int, float))
        and isinstance(start, (int, float))
        and completion_start > start
        else None
    )

    return {
        "ts": end if isinstance(end, (int, float)) else start,
        "event": "llm_request",
        "model_group": payload.get("model_group"),
        "model": payload.get("model"),
        "api_base": _host_only(payload.get("api_base")),
        "status": payload.get("status"),
        "error_class": error_info.get("error_class"),
        "latency_ms": latency_ms,
        "ttft_ms": ttft_ms,
        "prompt_tokens": payload.get("prompt_tokens"),
        "completion_tokens": payload.get("completion_tokens"),
        "cache_hit": payload.get("cache_hit"),
        "key_alias": metadata.get("user_api_key_alias"),
        "call_id": payload.get("litellm_call_id") or payload.get("id"),
        "trace_id": payload.get("trace_id"),
    }


class RequestMetrics(CustomLogger):
    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        print(json.dumps(build_record(kwargs, response_obj, start_time, end_time)), flush=True)

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        print(json.dumps(build_record(kwargs, response_obj, start_time, end_time)), flush=True)


proxy_handler_instance = RequestMetrics()
