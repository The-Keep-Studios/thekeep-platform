#!/usr/bin/env python3
"""Validate the fake TKP-side EspoCRM assistant contract."""

from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_PATH = PROJECT_ROOT / "examples" / "espocrm-assistant.instance.example.json"
DEPLOYMENT_PATH = PROJECT_ROOT / "kubernetes/apps/espocrm-assistant/deployment.yaml"
README_PATH = PROJECT_ROOT / "README.md"

IMAGE_RE = re.compile(
    r"^ghcr\.io/the-keep-studios/espocrm-assistant@sha256:[0-9a-f]{64}$"
)
DNS_LABEL_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
SECRET_KEY_RE = re.compile(r"^[A-Z0-9_]+$")
ALLOWED_ENTITIES = {"Lead", "Opportunity", "Account", "Contact", "Task", "Email"}
READONLY_ENTITIES = {"Email"}
ALLOWED_ACTIONS = {"create", "update"}
REQUIRED_TOP_LEVEL = {
    "contract_version",
    "purpose",
    "assistant_image",
    "source_boundary",
    "runtime_boundary",
    "secrets",
    "allowed_entities",
    "write_policy",
    "fixtures",
    "dry_run_change_sets",
}
BANNED_STRING_VALUES = {
    "gmail.com",
    "linkedin.com",
    "thekeepstudios.com",
    "greenhouse.io",
    "lever.co",
    "ashbyhq.com",
    "CHANGE_ME",
    "REPLACE_ME",
}


class ContractError(ValueError):
    """Raised for expected contract validation failures."""


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


def require_dns_label(value: str, context: str) -> None:
    if len(value) > 63 or not DNS_LABEL_RE.match(value):
        fail(f"{context} must be a DNS-safe label: {value}")


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


def validate_no_private_values(data: dict[str, Any]) -> None:
    for value in walk_strings(data):
        lower_value = value.lower()
        if "http://" in lower_value or "https://" in lower_value:
            fail(f"Contract must not contain service URLs: {value}")
        for banned in BANNED_STRING_VALUES:
            if banned.lower() in lower_value:
                fail(f"Contract contains banned public/private marker: {banned}")
        if re.search(r"\b(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.", value):
            fail(f"Contract contains a private network address: {value}")


def load_contract() -> dict[str, Any]:
    raw = EXAMPLE_PATH.read_text(encoding="utf-8")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"{EXAMPLE_PATH} is not valid JSON: {exc}")
    return require_mapping(data, str(EXAMPLE_PATH))


def validate_top_level(data: dict[str, Any]) -> None:
    missing = sorted(REQUIRED_TOP_LEVEL - set(data))
    if missing:
        fail(f"Contract is missing required fields: {', '.join(missing)}")
    if not IMAGE_RE.match(require_string(data["assistant_image"], "assistant_image")):
        fail("assistant_image must be an immutable espocrm-assistant sha256 digest.")

    deployment = DEPLOYMENT_PATH.read_text(encoding="utf-8")
    if data["assistant_image"] not in deployment:
        fail("assistant_image must match the image consumed by TKP deployment YAML.")


def validate_source_boundary(data: dict[str, Any]) -> None:
    source = require_mapping(data["source_boundary"], "source_boundary")
    if source.get("service_source_repo") != "The-Keep-Studios/espocrm-assistant":
        fail("source_boundary.service_source_repo must identify the external service repo.")
    require_bool(source.get("tkp_contract_only"), True, "source_boundary.tkp_contract_only")
    require_bool(
        source.get("no_service_source_in_tkp"),
        True,
        "source_boundary.no_service_source_in_tkp",
    )


def validate_runtime_boundary(data: dict[str, Any]) -> None:
    runtime = require_mapping(data["runtime_boundary"], "runtime_boundary")
    if runtime.get("namespace") != "espocrm":
        fail("runtime_boundary.namespace must be espocrm.")
    if runtime.get("service_name") != "espocrm-assistant":
        fail("runtime_boundary.service_name must be espocrm-assistant.")
    if runtime.get("public_exposure") != "none":
        fail("runtime_boundary.public_exposure must be none.")
    if runtime.get("mcp_port_name") != "mcp":
        fail("runtime_boundary.mcp_port_name must be mcp.")
    if runtime.get("approval_port_name") != "approval":
        fail("runtime_boundary.approval_port_name must be approval.")
    require_bool(
        runtime.get("browser_automation_allowed"),
        False,
        "runtime_boundary.browser_automation_allowed",
    )
    require_bool(
        runtime.get("network_calls_by_validator"),
        False,
        "runtime_boundary.network_calls_by_validator",
    )


def validate_secret_refs(data: dict[str, Any]) -> None:
    secrets = require_mapping(data["secrets"], "secrets")
    required = {
        "read_api_key_secret_ref",
        "write_api_key_secret_ref",
        "assistant_token_secret_ref",
        "assistant_apply_token_secret_ref",
    }
    missing = sorted(required - set(secrets))
    if missing:
        fail(f"secrets is missing required refs: {', '.join(missing)}")

    for name, ref_value in secrets.items():
        if not name.endswith("_secret_ref"):
            fail(f"secrets.{name} must be named as a secret reference.")
        ref = require_mapping(ref_value, f"secrets.{name}")
        unexpected = sorted(set(ref) - {"name", "key", "purpose"})
        if unexpected:
            fail(f"secrets.{name} contains non-reference fields: {', '.join(unexpected)}")
        secret_name = require_string(ref.get("name"), f"secrets.{name}.name")
        secret_key = require_string(ref.get("key"), f"secrets.{name}.key")
        require_string(ref.get("purpose"), f"secrets.{name}.purpose")
        require_dns_label(secret_name, f"secrets.{name}.name")
        if not SECRET_KEY_RE.match(secret_key):
            fail(f"secrets.{name}.key must be an uppercase Kubernetes key.")


def validate_entities(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    entities: dict[str, dict[str, Any]] = {}
    for index, raw_entity in enumerate(require_list(data["allowed_entities"], "allowed_entities")):
        entity = require_mapping(raw_entity, f"allowed_entities[{index}]")
        name = require_string(entity.get("entity"), f"allowed_entities[{index}].entity")
        if name not in ALLOWED_ENTITIES:
            fail(f"Unsupported entity in contract: {name}")
        if name in entities:
            fail(f"Duplicate entity contract: {name}")
        require_bool(entity.get("read"), True, f"allowed_entities[{index}].read")
        require_bool(entity.get("delete"), False, f"allowed_entities[{index}].delete")

        writes = entity.get("write")
        if not isinstance(writes, list):
            fail(f"allowed_entities[{index}].write must be a list.")
        for action in writes:
            if action not in ALLOWED_ACTIONS:
                fail(f"{name} has unsupported write action: {action}")
        if name in READONLY_ENTITIES and writes:
            fail(f"{name} must stay read-only in the assistant contract.")
        if writes:
            require_bool(
                entity.get("required_approval"),
                True,
                f"allowed_entities[{index}].required_approval",
            )
        fields = require_list(entity.get("allowed_fields"), f"allowed_entities[{index}].allowed_fields")
        for field in fields:
            require_string(field, f"allowed_entities[{index}].allowed_fields item")
        entities[name] = entity

    missing = sorted(ALLOWED_ENTITIES - set(entities))
    if missing:
        fail(f"Contract does not cover required EspoCRM entities: {', '.join(missing)}")
    return entities


def validate_write_policy(data: dict[str, Any]) -> None:
    policy = require_mapping(data["write_policy"], "write_policy")
    if policy.get("write_approval_mode") != "human-required":
        fail("write_policy.write_approval_mode must be human-required.")
    for field in (
        "dry_run_required",
        "audit_log_required",
        "no_delete_policy",
        "human_approval_gate_required",
        "opportunity_requires_reciprocal_signal",
    ):
        require_bool(policy.get(field), True, f"write_policy.{field}")
    for field in ("auto_apply_allowed", "unsolicited_outreach_allowed"):
        require_bool(policy.get(field), False, f"write_policy.{field}")
    audit_ref = require_string(policy.get("audit_log_ref"), "write_policy.audit_log_ref")
    require_dns_label(audit_ref, "write_policy.audit_log_ref")


def validate_fixtures(data: dict[str, Any]) -> set[str]:
    fixture_ids: set[str] = set()
    allowed_workflows = {
        "recruiter_outreach",
        "ats_confirmation",
        "cold_application_lead",
    }
    allowed_classifications = {
        "lead",
        "priority_lead",
        "opportunity_candidate",
    }
    for index, raw_fixture in enumerate(require_list(data["fixtures"], "fixtures")):
        fixture = require_mapping(raw_fixture, f"fixtures[{index}]")
        fixture_id = require_string(fixture.get("fixture_id"), f"fixtures[{index}].fixture_id")
        if fixture_id in fixture_ids:
            fail(f"Duplicate fixture_id: {fixture_id}")
        fixture_ids.add(fixture_id)
        workflow = require_string(fixture.get("workflow"), f"fixtures[{index}].workflow")
        if workflow not in allowed_workflows:
            fail(f"Unsupported fixture workflow: {workflow}")
        classification = require_string(
            fixture.get("classification"), f"fixtures[{index}].classification"
        )
        if classification not in allowed_classifications:
            fail(f"Unsupported fixture classification: {classification}")
        source = require_mapping(fixture.get("source"), f"fixtures[{index}].source")
        sender = require_string(source.get("sender"), f"fixtures[{index}].source.sender")
        sender_domain = sender.rsplit("@", 1)[-1]
        if sender_domain != "example.test" and not sender_domain.endswith(".example.test"):
            fail(f"Fixture sender must use example.test: {sender}")
        require_string(source.get("subject"), f"fixtures[{index}].source.subject")
        require_string(source.get("received_at"), f"fixtures[{index}].source.received_at")
        require_string(fixture.get("next_action"), f"fixtures[{index}].next_action")
        require_bool(fixture.get("approval_needed"), True, f"fixtures[{index}].approval_needed")
        if not isinstance(fixture.get("reciprocal_signal"), bool):
            fail(f"fixtures[{index}].reciprocal_signal must be boolean.")
    return fixture_ids


def validate_change_sets(
    data: dict[str, Any],
    fixture_ids: set[str],
    entities: dict[str, dict[str, Any]],
) -> None:
    for index, raw_change_set in enumerate(
        require_list(data["dry_run_change_sets"], "dry_run_change_sets")
    ):
        change_set = require_mapping(raw_change_set, f"dry_run_change_sets[{index}]")
        require_string(
            change_set.get("change_set_id"),
            f"dry_run_change_sets[{index}].change_set_id",
        )
        source_fixture_id = require_string(
            change_set.get("source_fixture_id"),
            f"dry_run_change_sets[{index}].source_fixture_id",
        )
        if source_fixture_id not in fixture_ids:
            fail(f"Unknown source_fixture_id: {source_fixture_id}")
        require_bool(change_set.get("dry_run"), True, f"dry_run_change_sets[{index}].dry_run")
        require_bool(
            change_set.get("approval_required"),
            True,
            f"dry_run_change_sets[{index}].approval_required",
        )
        require_bool(
            change_set.get("delete_allowed"),
            False,
            f"dry_run_change_sets[{index}].delete_allowed",
        )

        for change_index, raw_change in enumerate(
            require_list(change_set.get("changes"), f"dry_run_change_sets[{index}].changes")
        ):
            context = f"dry_run_change_sets[{index}].changes[{change_index}]"
            change = require_mapping(raw_change, context)
            action = require_string(change.get("action"), f"{context}.action")
            if action not in ALLOWED_ACTIONS:
                fail(f"{context}.action is not allowed: {action}")
            entity_name = require_string(change.get("entity"), f"{context}.entity")
            if entity_name not in entities:
                fail(f"{context}.entity is not covered by allowed_entities: {entity_name}")
            if action not in entities[entity_name]["write"]:
                fail(f"{context}.action is not allowed for {entity_name}: {action}")
            if change.get("human_approval_gate") != "required":
                fail(f"{context}.human_approval_gate must be required.")
            require_bool(change.get("no_delete"), True, f"{context}.no_delete")
            require_string(change.get("source_attribution"), f"{context}.source_attribution")
            require_string(change.get("audit_note"), f"{context}.audit_note")
            fields = require_mapping(change.get("fields"), f"{context}.fields")
            allowed_fields = set(entities[entity_name]["allowed_fields"])
            for field in fields:
                if field not in allowed_fields:
                    fail(f"{context}.fields.{field} is not allowed for {entity_name}.")


def validate_doc_links() -> None:
    readme = README_PATH.read_text(encoding="utf-8")
    for required in (
        "examples/espocrm-assistant.instance.example.json",
        "scripts/test-espocrm-assistant-contract.py",
    ):
        if required not in readme:
            fail(f"{README_PATH} must reference {required}.")


def validate_contract(data: dict[str, Any]) -> None:
    validate_top_level(data)
    validate_no_private_values(data)
    validate_source_boundary(data)
    validate_runtime_boundary(data)
    validate_secret_refs(data)
    entities = validate_entities(data)
    validate_write_policy(data)
    fixture_ids = validate_fixtures(data)
    validate_change_sets(data, fixture_ids, entities)


def expect_failure(label: str, data: dict[str, Any]) -> None:
    try:
        validate_contract(data)
    except ContractError:
        return
    fail(f"Negative fixture unexpectedly passed: {label}")


def run_negative_checks(valid_data: dict[str, Any]) -> None:
    missing_image = copy.deepcopy(valid_data)
    del missing_image["assistant_image"]
    expect_failure("missing assistant_image", missing_image)

    literal_secret = copy.deepcopy(valid_data)
    literal_secret["secrets"]["read_api_key_secret_ref"]["value"] = "not-a-real-token"
    expect_failure("literal secret value", literal_secret)

    delete_change = copy.deepcopy(valid_data)
    delete_change["dry_run_change_sets"][0]["changes"][0]["action"] = "delete"
    expect_failure("delete action", delete_change)

    public_exposure = copy.deepcopy(valid_data)
    public_exposure["runtime_boundary"]["public_exposure"] = "internet"
    expect_failure("public exposure", public_exposure)


def main() -> None:
    try:
        data = load_contract()
        validate_contract(data)
        validate_doc_links()
        run_negative_checks(data)
    except ContractError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc
    print(
        "Validated fake EspoCRM assistant contract, dry-run change sets, "
        "and negative safety fixtures."
    )


if __name__ == "__main__":
    main()
