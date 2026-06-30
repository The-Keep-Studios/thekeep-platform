#!/usr/bin/env python3
"""Validate fake MCP gateway preflight metadata and upstream policy."""

from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXAMPLES_DIR = PROJECT_ROOT / "examples"
README_PATH = PROJECT_ROOT / "README.md"
PROTECTED_RESOURCE_PATH = EXAMPLES_DIR / "mcp-gateway.protected-resource.example.json"
AUTHORIZATION_SERVER_PATH = EXAMPLES_DIR / "mcp-gateway.authorization-server.example.json"
UPSTREAMS_PATH = EXAMPLES_DIR / "mcp-gateway.upstreams.example.json"

REQUIRED_PROTECTED_RESOURCE_FIELDS = {
    "resource",
    "resource_name",
    "authorization_servers",
    "scopes_supported",
    "bearer_methods_supported",
    "mcp_transport",
    "metadata_fixture_only",
}
REQUIRED_AUTH_SERVER_FIELDS = {
    "issuer",
    "authorization_endpoint",
    "token_endpoint",
    "jwks_uri",
    "response_types_supported",
    "grant_types_supported",
    "code_challenge_methods_supported",
    "scopes_supported",
    "resource_parameter_supported",
    "metadata_fixture_only",
}
REQUIRED_UPSTREAM_FIELDS = {
    "upstream_id",
    "display_name",
    "mcp_endpoint",
    "transport",
    "credential_secret_ref",
    "allowed_subjects",
    "tool_policy",
    "tools",
    "blocked_tool_examples",
    "limits",
}
SECRET_REF_FIELDS = {"name", "key"}
DNS_LABEL_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
SECRET_KEY_RE = re.compile(r"^[A-Z0-9_]+$")
BANNED_VALUE_MARKERS = {
    "thekeepstudios.com",
    "projects.thekeepstudios.com",
    "leantime.thekeepstudios.com",
    "gmail.com",
    "CHANGE_ME",
    "REPLACE_ME",
}


class ContractError(ValueError):
    """Raised for expected MCP gateway contract failures."""


def fail(message: str) -> None:
    raise ContractError(message)


def require_mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{context} must be a mapping.")
    return value


def require_list(value: Any, context: str) -> list[Any]:
    if not isinstance(value, list) or not value:
        fail(f"{context} must be a non-empty list.")
    return value


def require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} must be a non-empty string.")
    return value


def require_bool(value: Any, expected: bool, context: str) -> None:
    if value is not expected:
        fail(f"{context} must be {expected}.")


def require_fields(mapping: dict[str, Any], required: set[str], context: str) -> None:
    missing = sorted(required - set(mapping))
    if missing:
        fail(f"{context} is missing required fields: {', '.join(missing)}")


def require_dns_label(value: str, context: str) -> None:
    if len(value) > 63 or not DNS_LABEL_RE.match(value):
        fail(f"{context} must be a DNS-safe label: {value}")


def require_fake_https_url(value: Any, context: str) -> str:
    url = require_string(value, context)
    parsed = urlparse(url)
    if parsed.scheme != "https":
        fail(f"{context} must use https: {url}")
    if parsed.hostname is None or not parsed.hostname.endswith(".example.invalid"):
        fail(f"{context} must use a fake .example.invalid host: {url}")
    return url


def walk_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        strings: list[str] = []
        for item in value.values():
            strings.extend(walk_strings(item))
        return strings
    if isinstance(value, list):
        strings = []
        for item in value:
            strings.extend(walk_strings(item))
        return strings
    return []


def validate_no_private_values(*documents: dict[str, Any]) -> None:
    for document in documents:
        for value in walk_strings(document):
            lower_value = value.lower()
            for banned in BANNED_VALUE_MARKERS:
                if banned.lower() in lower_value:
                    fail(f"Metadata contains banned public/private marker: {banned}")
            if re.search(r"\b(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.", value):
                fail(f"Metadata contains a private network address: {value}")


def load_json(path: Path) -> dict[str, Any]:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        fail(f"Missing metadata example: {path}")
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")
    return require_mapping(loaded, str(path))


def validate_protected_resource(metadata: dict[str, Any]) -> None:
    require_fields(metadata, REQUIRED_PROTECTED_RESOURCE_FIELDS, "protected resource")
    require_fake_https_url(metadata["resource"], "protected_resource.resource")
    require_string(metadata["resource_name"], "protected_resource.resource_name")
    require_bool(
        metadata.get("metadata_fixture_only"),
        True,
        "protected_resource.metadata_fixture_only",
    )
    authorization_servers = require_list(
        metadata["authorization_servers"],
        "protected_resource.authorization_servers",
    )
    for index, server in enumerate(authorization_servers):
        require_fake_https_url(server, f"protected_resource.authorization_servers[{index}]")

    scopes = set(require_list(metadata["scopes_supported"], "protected_resource.scopes_supported"))
    if not {"mcp:read", "mcp:write:approved"} <= scopes:
        fail("protected_resource.scopes_supported must include read and approved-write scopes.")
    if "header" not in require_list(
        metadata["bearer_methods_supported"],
        "protected_resource.bearer_methods_supported",
    ):
        fail("protected_resource.bearer_methods_supported must include header.")
    if metadata.get("mcp_transport") != "streamable-http":
        fail("protected_resource.mcp_transport must be streamable-http.")
    if "jwks_uri" in metadata:
        require_fake_https_url(metadata["jwks_uri"], "protected_resource.jwks_uri")


def validate_authorization_server(metadata: dict[str, Any]) -> None:
    require_fields(metadata, REQUIRED_AUTH_SERVER_FIELDS, "authorization server")
    issuer = require_fake_https_url(metadata["issuer"], "authorization_server.issuer")
    for field in ("authorization_endpoint", "token_endpoint", "jwks_uri"):
        require_fake_https_url(metadata[field], f"authorization_server.{field}")
    require_bool(
        metadata.get("metadata_fixture_only"),
        True,
        "authorization_server.metadata_fixture_only",
    )
    require_bool(
        metadata.get("resource_parameter_supported"),
        True,
        "authorization_server.resource_parameter_supported",
    )
    if "code" not in require_list(
        metadata["response_types_supported"],
        "authorization_server.response_types_supported",
    ):
        fail("authorization_server.response_types_supported must include code.")
    grants = set(
        require_list(
            metadata["grant_types_supported"],
            "authorization_server.grant_types_supported",
        )
    )
    if "authorization_code" not in grants:
        fail("authorization_server.grant_types_supported must include authorization_code.")
    if "S256" not in require_list(
        metadata["code_challenge_methods_supported"],
        "authorization_server.code_challenge_methods_supported",
    ):
        fail("authorization_server.code_challenge_methods_supported must include S256.")
    scopes = set(require_list(metadata["scopes_supported"], "authorization_server.scopes_supported"))
    if not {"openid", "mcp:read", "mcp:write:approved"} <= scopes:
        fail("authorization_server.scopes_supported is missing required scopes.")
    if not issuer.endswith("/"):
        fail("authorization_server.issuer should be a normalized issuer URL ending in /.")


def validate_secret_ref(value: Any, context: str) -> None:
    ref = require_mapping(value, context)
    unexpected = sorted(set(ref) - SECRET_REF_FIELDS)
    if unexpected:
        fail(f"{context} must contain only secret reference fields: {', '.join(unexpected)}")
    name = require_string(ref.get("name"), f"{context}.name")
    key = require_string(ref.get("key"), f"{context}.key")
    require_dns_label(name, f"{context}.name")
    if not SECRET_KEY_RE.match(key):
        fail(f"{context}.key must be an uppercase Kubernetes key.")


def validate_upstreams(registry: dict[str, Any]) -> None:
    if registry.get("default_policy") != "deny":
        fail("upstreams.default_policy must be deny.")
    require_bool(
        registry.get("gateway_is_generic_http_proxy"),
        False,
        "upstreams.gateway_is_generic_http_proxy",
    )
    require_bool(registry.get("audit_log_required"), True, "upstreams.audit_log_required")
    require_bool(registry.get("secret_logging_allowed"), False, "upstreams.secret_logging_allowed")

    upstreams = require_list(registry.get("upstreams"), "upstreams.upstreams")
    seen_ids: set[str] = set()
    for upstream_index, raw_upstream in enumerate(upstreams):
        context = f"upstreams[{upstream_index}]"
        upstream = require_mapping(raw_upstream, context)
        require_fields(upstream, REQUIRED_UPSTREAM_FIELDS, context)
        upstream_id = require_string(upstream["upstream_id"], f"{context}.upstream_id")
        require_dns_label(upstream_id, f"{context}.upstream_id")
        if upstream_id in seen_ids:
            fail(f"Duplicate upstream_id: {upstream_id}")
        seen_ids.add(upstream_id)
        require_string(upstream["display_name"], f"{context}.display_name")
        require_fake_https_url(upstream["mcp_endpoint"], f"{context}.mcp_endpoint")
        if upstream.get("transport") != "streamable-http":
            fail(f"{context}.transport must be streamable-http.")
        validate_secret_ref(upstream["credential_secret_ref"], f"{context}.credential_secret_ref")
        subjects = require_list(upstream["allowed_subjects"], f"{context}.allowed_subjects")
        for subject in subjects:
            subject_value = require_string(subject, f"{context}.allowed_subjects item")
            if not subject_value.startswith(("user:", "group:")):
                fail(f"{context}.allowed_subjects entries must be user: or group: scoped.")

        policy = require_mapping(upstream["tool_policy"], f"{context}.tool_policy")
        if policy.get("unknown_tools") != "deny":
            fail(f"{context}.tool_policy.unknown_tools must be deny.")
        if policy.get("read_scope") != "mcp:read":
            fail(f"{context}.tool_policy.read_scope must be mcp:read.")
        if policy.get("write_scope") != "mcp:write:approved":
            fail(f"{context}.tool_policy.write_scope must be mcp:write:approved.")

        tools = require_list(upstream["tools"], f"{context}.tools")
        for tool_index, raw_tool in enumerate(tools):
            tool_context = f"{context}.tools[{tool_index}]"
            tool = require_mapping(raw_tool, tool_context)
            name = require_string(tool.get("name"), f"{tool_context}.name")
            if name in set(upstream.get("blocked_tool_examples", [])):
                fail(f"{tool_context}.name must not also be listed as blocked.")
            mode = require_string(tool.get("mode"), f"{tool_context}.mode")
            if mode not in {"read", "write"}:
                fail(f"{tool_context}.mode must be read or write.")
            require_bool(tool.get("allowed"), True, f"{tool_context}.allowed")
            require_bool(tool.get("audit"), True, f"{tool_context}.audit")
            approval_required = tool.get("approval_required")
            if mode == "write":
                require_bool(approval_required, True, f"{tool_context}.approval_required")
            else:
                require_bool(approval_required, False, f"{tool_context}.approval_required")

        blocked = require_list(upstream["blocked_tool_examples"], f"{context}.blocked_tool_examples")
        for blocked_name in blocked:
            require_string(blocked_name, f"{context}.blocked_tool_examples item")

        limits = require_mapping(upstream["limits"], f"{context}.limits")
        for limit_name in (
            "request_timeout_seconds",
            "max_request_bytes",
            "max_response_bytes",
            "rate_limit_per_minute",
        ):
            if not isinstance(limits.get(limit_name), int) or limits[limit_name] <= 0:
                fail(f"{context}.limits.{limit_name} must be a positive integer.")


def validate_cross_document_links(
    protected_resource: dict[str, Any],
    authorization_server: dict[str, Any],
) -> None:
    authorization_servers = protected_resource["authorization_servers"]
    if authorization_server["issuer"] not in authorization_servers:
        fail("authorization_server.issuer must be listed by protected_resource.authorization_servers.")


def validate_doc_links() -> None:
    readme = README_PATH.read_text(encoding="utf-8")
    for required in (
        "examples/mcp-gateway.protected-resource.example.json",
        "examples/mcp-gateway.authorization-server.example.json",
        "examples/mcp-gateway.upstreams.example.json",
        "scripts/test-mcp-gateway-contract.py",
        "scripts/run-mcp-gateway-fixture.py",
    ):
        if required not in readme:
            fail(f"{README_PATH} must reference {required}.")


def validate_all(
    protected_resource: dict[str, Any],
    authorization_server: dict[str, Any],
    upstreams: dict[str, Any],
) -> None:
    validate_no_private_values(protected_resource, authorization_server, upstreams)
    validate_protected_resource(protected_resource)
    validate_authorization_server(authorization_server)
    validate_cross_document_links(protected_resource, authorization_server)
    validate_upstreams(upstreams)


def expect_failure(
    label: str,
    protected_resource: dict[str, Any],
    authorization_server: dict[str, Any],
    upstreams: dict[str, Any],
) -> None:
    try:
        validate_all(protected_resource, authorization_server, upstreams)
    except ContractError:
        return
    fail(f"Negative fixture unexpectedly passed: {label}")


def run_negative_checks(
    protected_resource: dict[str, Any],
    authorization_server: dict[str, Any],
    upstreams: dict[str, Any],
) -> None:
    missing_resource = copy.deepcopy(protected_resource)
    del missing_resource["resource"]
    expect_failure("missing protected resource", missing_resource, authorization_server, upstreams)

    real_domain = copy.deepcopy(protected_resource)
    real_domain["resource"] = "https://mcp.thekeepstudios.com/leantime"
    expect_failure("real domain", real_domain, authorization_server, upstreams)

    secret_value = copy.deepcopy(upstreams)
    secret_value["upstreams"][0]["credential_secret_ref"]["value"] = "not-a-real-token"
    expect_failure("literal upstream secret", protected_resource, authorization_server, secret_value)

    open_proxy = copy.deepcopy(upstreams)
    open_proxy["gateway_is_generic_http_proxy"] = True
    expect_failure("generic open proxy", protected_resource, authorization_server, open_proxy)

    unknown_tools_allowed = copy.deepcopy(upstreams)
    unknown_tools_allowed["upstreams"][0]["tool_policy"]["unknown_tools"] = "allow"
    expect_failure(
        "unknown tools allowed",
        protected_resource,
        authorization_server,
        unknown_tools_allowed,
    )

    write_without_approval = copy.deepcopy(upstreams)
    write_without_approval["upstreams"][0]["tools"][2]["approval_required"] = False
    expect_failure(
        "write tool without approval",
        protected_resource,
        authorization_server,
        write_without_approval,
    )


def main() -> None:
    try:
        protected_resource = load_json(PROTECTED_RESOURCE_PATH)
        authorization_server = load_json(AUTHORIZATION_SERVER_PATH)
        upstreams = load_json(UPSTREAMS_PATH)
        validate_all(protected_resource, authorization_server, upstreams)
        validate_doc_links()
        run_negative_checks(protected_resource, authorization_server, upstreams)
    except ContractError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc
    print("Validated fake MCP gateway metadata, upstream policy, and negative fixtures.")


if __name__ == "__main__":
    main()
