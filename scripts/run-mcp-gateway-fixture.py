#!/usr/bin/env python3
"""Run a local-only fake MCP gateway policy simulation."""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY = PROJECT_ROOT / "examples" / "mcp-gateway.upstreams.example.json"
DEFAULT_UPSTREAM = "fake-leantime"
DEFAULT_SUBJECT = "group:platform-operators"
DEFAULT_TOOL = "leantime.projects.list"
READ_RESULTS = {
    "leantime.projects.list": {
        "projects": [
            {
                "id": "fake-project-001",
                "name": "Fake automation intake",
                "status": "active",
            }
        ]
    },
    "leantime.tasks.list": {
        "tasks": [
            {
                "id": "fake-task-001",
                "title": "Review fake intake report",
                "status": "open",
            }
        ]
    },
}


class GatewayFixtureError(ValueError):
    """Raised for expected fake gateway policy failures."""


def fail(message: str) -> None:
    raise GatewayFixtureError(message)


def require_mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{context} must be a mapping.")
    return value


def require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} must be a non-empty string.")
    return value


def load_registry(path: Path) -> dict[str, Any]:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        fail(f"Missing upstream registry: {path}")
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")
    return require_mapping(loaded, str(path))


def find_upstream(registry: dict[str, Any], upstream_id: str) -> dict[str, Any]:
    for raw_upstream in registry.get("upstreams", []):
        upstream = require_mapping(raw_upstream, "upstreams item")
        if upstream.get("upstream_id") == upstream_id:
            return upstream
    fail(f"Unknown upstream: {upstream_id}")


def find_tool(registry: dict[str, Any], upstream: dict[str, Any], tool_name: str) -> dict[str, Any]:
    for raw_tool in upstream.get("tools", []):
        tool = require_mapping(raw_tool, "tools item")
        if tool.get("name") == tool_name:
            return tool

    default_policy = registry.get("default_policy")
    unknown_policy = require_mapping(
        upstream.get("tool_policy"),
        "upstream.tool_policy",
    ).get("unknown_tools")
    if default_policy == "deny" and unknown_policy == "deny":
        fail(f"Denied unknown tool by default: {tool_name}")
    fail(f"Unknown tool policy is not default-deny for: {tool_name}")


def authorize_subject(upstream: dict[str, Any], subject: str) -> None:
    allowed_subjects = upstream.get("allowed_subjects")
    if not isinstance(allowed_subjects, list) or subject not in allowed_subjects:
        fail(f"Denied subject without upstream grant: {subject}")


def authorize_tool(upstream: dict[str, Any], tool: dict[str, Any], scope: str, approved: bool) -> None:
    tool_policy = require_mapping(upstream.get("tool_policy"), "upstream.tool_policy")
    mode = require_string(tool.get("mode"), "tool.mode")
    if tool.get("allowed") is not True:
        fail(f"Denied disallowed tool: {tool.get('name')}")

    if mode == "read":
        required_scope = require_string(tool_policy.get("read_scope"), "tool_policy.read_scope")
    elif mode == "write":
        required_scope = require_string(tool_policy.get("write_scope"), "tool_policy.write_scope")
        if tool.get("approval_required") is not True:
            fail(f"Write tool is missing approval-required policy: {tool.get('name')}")
        if not approved:
            fail(f"Denied write tool without human approval: {tool.get('name')}")
    else:
        fail(f"Unsupported tool mode: {mode}")

    if scope != required_scope:
        fail(f"Denied tool with insufficient scope: required {required_scope}, got {scope}")


def audit_event(
    upstream: dict[str, Any],
    subject: str,
    tool: dict[str, Any],
    outcome: str,
) -> dict[str, Any]:
    return {
        "subject": subject,
        "upstream_id": upstream["upstream_id"],
        "tool": tool["name"],
        "mode": tool["mode"],
        "approval_required": tool["approval_required"],
        "credential_secret_ref": "REDACTED_SECRET_REF",
        "outcome": outcome,
    }


def invoke_tool(
    registry: dict[str, Any],
    upstream_id: str,
    subject: str,
    tool_name: str,
    scope: str,
    approved: bool,
) -> dict[str, Any]:
    upstream = find_upstream(registry, upstream_id)
    authorize_subject(upstream, subject)
    tool = find_tool(registry, upstream, tool_name)
    authorize_tool(upstream, tool, scope, approved)

    if tool["mode"] == "read":
        result = {
            "proxied": "simulated-read-only",
            "network_calls": 0,
            "write_performed": False,
            "data": copy.deepcopy(READ_RESULTS.get(tool_name, {"items": []})),
        }
        outcome = "allowed"
    else:
        result = {
            "proxied": "not-run-in-fixture",
            "network_calls": 0,
            "write_performed": False,
            "message": "Write tool remains approval-required; fixture does not mutate upstreams.",
        }
        outcome = "approval-required"

    return {
        "gateway": "fake-local-mcp-gateway",
        "registry_version": registry.get("registry_version"),
        "audit": audit_event(upstream, subject, tool, outcome),
        "result": result,
    }


def render_tools(registry: dict[str, Any], upstream_id: str) -> dict[str, Any]:
    upstream = find_upstream(registry, upstream_id)
    return {
        "upstream_id": upstream_id,
        "default_policy": registry.get("default_policy"),
        "tools": [
            {
                "name": tool["name"],
                "mode": tool["mode"],
                "approval_required": tool["approval_required"],
            }
            for tool in upstream.get("tools", [])
        ],
    }


def expect_failure(label: str, func: Any) -> None:
    try:
        func()
    except GatewayFixtureError:
        return
    fail(f"Negative gateway fixture unexpectedly passed: {label}")


def assert_redacted(output: dict[str, Any], upstream: dict[str, Any]) -> None:
    encoded = json.dumps(output, sort_keys=True)
    secret_ref = require_mapping(
        upstream.get("credential_secret_ref"),
        "upstream.credential_secret_ref",
    )
    for value in secret_ref.values():
        if str(value) in encoded:
            fail("Gateway output leaked an upstream secret reference.")


def run_self_test(registry: dict[str, Any]) -> None:
    upstream = find_upstream(registry, DEFAULT_UPSTREAM)
    success = invoke_tool(
        registry,
        DEFAULT_UPSTREAM,
        DEFAULT_SUBJECT,
        DEFAULT_TOOL,
        "mcp:read",
        approved=False,
    )
    assert_redacted(success, upstream)

    expect_failure(
        "unauthorized subject",
        lambda: invoke_tool(
            registry,
            DEFAULT_UPSTREAM,
            "user:unauthorized-example",
            DEFAULT_TOOL,
            "mcp:read",
            approved=False,
        ),
    )
    expect_failure(
        "unknown tool",
        lambda: invoke_tool(
            registry,
            DEFAULT_UPSTREAM,
            DEFAULT_SUBJECT,
            "leantime.admin.delete_project",
            "mcp:read",
            approved=False,
        ),
    )
    expect_failure(
        "write without approval",
        lambda: invoke_tool(
            registry,
            DEFAULT_UPSTREAM,
            DEFAULT_SUBJECT,
            "leantime.tasks.create",
            "mcp:write:approved",
            approved=False,
        ),
    )
    expect_failure(
        "read with write-only scope",
        lambda: invoke_tool(
            registry,
            DEFAULT_UPSTREAM,
            DEFAULT_SUBJECT,
            DEFAULT_TOOL,
            "mcp:write:approved",
            approved=False,
        ),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--registry",
        type=Path,
        default=DEFAULT_REGISTRY,
        help="Path to the fake MCP upstream registry.",
    )
    parser.add_argument("--upstream", default=DEFAULT_UPSTREAM)
    parser.add_argument("--subject", default=DEFAULT_SUBJECT)
    parser.add_argument("--tool", default=DEFAULT_TOOL)
    parser.add_argument("--scope", default="mcp:read")
    parser.add_argument(
        "--approved",
        action="store_true",
        help="Mark the simulated write call as human-approved.",
    )
    parser.add_argument(
        "--list-tools",
        action="store_true",
        help="List allowlisted tools and approval-required flags.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run built-in authorization, allowlist, approval, and redaction checks.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        registry = load_registry(args.registry)
        if args.self_test:
            run_self_test(registry)
            print("Validated fake MCP gateway runner policy behavior.")
            return
        if args.list_tools:
            output = render_tools(registry, args.upstream)
        else:
            output = invoke_tool(
                registry,
                args.upstream,
                args.subject,
                args.tool,
                args.scope,
                args.approved,
            )
    except GatewayFixtureError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc

    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
