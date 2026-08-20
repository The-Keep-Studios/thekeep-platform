#!/usr/bin/env python3
"""Run a deterministic local automation fixture without secrets or network calls."""

from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = PROJECT_ROOT / "examples" / "automation-job-source.fixture.json"
REQUIRED_TOP_LEVEL = {
    "fixture_version",
    "source_name",
    "provider_contract",
    "items",
}
REQUIRED_ITEM_FIELDS = {
    "item_id",
    "source_kind",
    "source",
    "received_at",
    "company",
    "role",
    "description",
    "contact",
    "signals",
    "risk_flags",
}
REQUIRED_SOURCE_KINDS = {
    "application_confirmation",
    "client_inquiry",
    "job_lead",
    "recruiter_email",
}
ALLOWED_SOURCE_KINDS = REQUIRED_SOURCE_KINDS | {
    "community_board",
}
BANNED_FIXTURE_MARKERS = {
    "gmail.com",
    "yahoo.com",
    "outlook.com",
    "thekeepstudios.com",
    "linkedin.com",
    "espocrm",
    "leantime",
    "CHANGE_ME",
    "REPLACE_ME",
}
DETAIL_REQUIREMENTS_BY_SOURCE_KIND = {
    "application_confirmation": ["application_reference"],
    "client_inquiry": ["budget_range", "timeline", "decision_maker"],
    "job_lead": ["remote_policy"],
    "recruiter_email": ["reciprocal_signal_detail"],
}
REJECT_RISK_FLAGS = {"onsite_only", "low_fit", "spam", "outside_scope"}
RECIPROCAL_SIGNALS = {"human_reply", "inbound_inquiry", "interview_request", "warm_intro"}
SOURCE_EXPORT_REQUIRED_TOP_LEVEL = {
    "export_version",
    "source_system",
    "fixture_only",
    "records",
}
SOURCE_EXPORT_REQUIRED_RECORD_FIELDS = {
    "source_record_id",
    "source_kind",
    "source_name",
    "received_at",
    "sender",
    "subject",
    "company",
    "role",
    "body_excerpt",
    "signals",
    "risk_flags",
}
ALLOWED_SOURCE_EXPORT_SYSTEMS = {"redacted-mailbox-json"}


class FixtureError(ValueError):
    """Raised for invalid fake automation fixtures."""


@dataclass(frozen=True)
class ProviderStatus:
    name: str
    note: str


@dataclass(frozen=True)
class AutomationResult:
    item_id: str
    source_kind: str
    source: str
    company: str
    role: str
    recommendation: str
    recommendation_slug: str
    crm_classification: str
    recommended_crm_action: str
    summary: str
    next_action: str
    approval_required: bool
    source_attribution: str
    audit_note: str
    missing_fields: tuple[str, ...]
    dry_run_change_set: dict[str, Any] | None


def fail(message: str) -> None:
    raise FixtureError(message)


def require_mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{context} must be a mapping.")
    return value


def require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} must be a non-empty string.")
    return value


def require_bool(value: Any, expected: bool, context: str) -> None:
    if value is not expected:
        fail(f"{context} must be {expected}.")


def require_string_list(value: Any, context: str) -> list[str]:
    if not isinstance(value, list):
        fail(f"{context} must be a list.")
    strings = []
    for index, item in enumerate(value):
        strings.append(require_string(item, f"{context}[{index}]"))
    return strings


def require_optional_details(item: dict[str, Any], context: str) -> dict[str, Any]:
    if "details" not in item:
        return {}
    return require_mapping(item["details"], f"{context}.details")


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


def validate_no_private_fixture_values(data: dict[str, Any]) -> None:
    for value in walk_strings(data):
        lower_value = value.lower()
        if "http://" in lower_value or "https://" in lower_value:
            parsed = urlparse(value)
            if parsed.scheme != "https":
                fail(f"Fixture URLs must use https: {value}")
            if parsed.hostname is None or not parsed.hostname.endswith(".example.invalid"):
                fail(f"Fixture URLs must use fake .example.invalid hosts: {value}")
        if re.search(r"\b(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.", value):
            fail(f"Fixture contains a private network address: {value}")
        for banned in BANNED_FIXTURE_MARKERS:
            if banned.lower() in lower_value:
                fail(f"Fixture contains banned marker: {banned}")


def load_fixture(path: Path) -> dict[str, Any]:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        fail(f"Missing fixture: {path}")
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")
    return require_mapping(loaded, str(path))


def load_source_export(path: Path) -> dict[str, Any]:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        fail(f"Missing source export: {path}")
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")
    return require_mapping(loaded, str(path))


def validate_source_export(data: dict[str, Any]) -> None:
    missing = sorted(SOURCE_EXPORT_REQUIRED_TOP_LEVEL - set(data))
    if missing:
        fail(f"Source export is missing required fields: {', '.join(missing)}")
    require_string(data.get("export_version"), "export_version")
    source_system = require_string(data.get("source_system"), "source_system")
    if source_system not in ALLOWED_SOURCE_EXPORT_SYSTEMS:
        fail(f"Unsupported source export system: {source_system}")
    require_bool(data.get("fixture_only"), True, "fixture_only")
    validate_no_private_fixture_values(data)

    records = data.get("records")
    if not isinstance(records, list) or not records:
        fail("records must be a non-empty list.")

    seen_ids: set[str] = set()
    seen_source_kinds: set[str] = set()
    for index, raw_record in enumerate(records):
        record = require_mapping(raw_record, f"records[{index}]")
        missing_record = sorted(SOURCE_EXPORT_REQUIRED_RECORD_FIELDS - set(record))
        if missing_record:
            fail(f"records[{index}] is missing required fields: {', '.join(missing_record)}")
        source_record_id = require_string(
            record["source_record_id"],
            f"records[{index}].source_record_id",
        )
        if source_record_id in seen_ids:
            fail(f"records[{index}].source_record_id must be unique: {source_record_id}")
        seen_ids.add(source_record_id)
        source_kind = require_string(record["source_kind"], f"records[{index}].source_kind")
        if source_kind not in ALLOWED_SOURCE_KINDS:
            fail(f"records[{index}].source_kind is unsupported: {source_kind}")
        seen_source_kinds.add(source_kind)
        for field in (
            "source_name",
            "received_at",
            "sender",
            "subject",
            "company",
            "role",
            "body_excerpt",
        ):
            require_string(record[field], f"records[{index}].{field}")
        sender = require_string(record["sender"], f"records[{index}].sender")
        sender_domain = sender.rsplit("@", 1)[-1]
        if sender_domain != "example.test" and not sender_domain.endswith(".example.test"):
            fail(f"records[{index}].sender must use example.test: {sender}")
        if "source_url" in record:
            require_string(record["source_url"], f"records[{index}].source_url")
        require_string_list(record["signals"], f"records[{index}].signals")
        require_string_list(record["risk_flags"], f"records[{index}].risk_flags")
        details = require_optional_details(record, f"records[{index}]")
        for key, value in details.items():
            require_string(str(key), f"records[{index}].details key")
            if isinstance(value, bool):
                continue
            require_string(value, f"records[{index}].details.{key}")

    missing_source_kinds = sorted(REQUIRED_SOURCE_KINDS - seen_source_kinds)
    if missing_source_kinds:
        missing_names = ", ".join(missing_source_kinds)
        fail(f"Source export is missing required fake intake records: {missing_names}")


def normalize_duplicate_key(record: dict[str, Any]) -> tuple[str, str, str]:
    return (
        record["source_kind"].strip().lower(),
        record["company"].strip().lower(),
        record["role"].strip().lower(),
    )


def source_export_to_fixture(data: dict[str, Any]) -> dict[str, Any]:
    validate_source_export(data)
    duplicate_first_seen: dict[tuple[str, str, str], str] = {}
    items: list[dict[str, Any]] = []

    for raw_record in data["records"]:
        record = require_mapping(raw_record, "records item")
        details = dict(require_mapping(record.get("details", {}), "record.details"))
        details["source_record_id"] = record["source_record_id"]
        details["source_system"] = data["source_system"]
        details["source_subject"] = record["subject"]
        if "source_url" in record:
            details["source_url"] = record["source_url"]

        duplicate_key = normalize_duplicate_key(record)
        possible_duplicate_of = duplicate_first_seen.get(duplicate_key)
        if possible_duplicate_of:
            details["possible_duplicate_of"] = possible_duplicate_of
        else:
            duplicate_first_seen[duplicate_key] = record["source_record_id"]

        items.append(
            {
                "item_id": record["source_record_id"],
                "source_kind": record["source_kind"],
                "source": f"{data['source_system']}:{record['source_name']}",
                "received_at": record["received_at"],
                "company": record["company"],
                "role": record["role"],
                "description": record["body_excerpt"],
                "contact": record["sender"],
                "signals": record["signals"],
                "risk_flags": record["risk_flags"],
                "details": details,
            }
        )

    return {
        "fixture_version": data["export_version"],
        "source_name": data["source_system"],
        "provider_contract": {
            "default_provider": "fake-deterministic",
            "hosted_api_keys_required": False,
            "network_calls_by_default": False,
            "writes_allowed": False,
            "approval_required_for_external_actions": True,
        },
        "items": items,
    }


def validate_provider_contract(data: dict[str, Any]) -> None:
    contract = require_mapping(data.get("provider_contract"), "provider_contract")
    if contract.get("default_provider") != "fake-deterministic":
        fail("provider_contract.default_provider must be fake-deterministic.")
    require_bool(
        contract.get("hosted_api_keys_required"),
        False,
        "provider_contract.hosted_api_keys_required",
    )
    require_bool(
        contract.get("network_calls_by_default"),
        False,
        "provider_contract.network_calls_by_default",
    )
    require_bool(contract.get("writes_allowed"), False, "provider_contract.writes_allowed")
    require_bool(
        contract.get("approval_required_for_external_actions"),
        True,
        "provider_contract.approval_required_for_external_actions",
    )


def validate_fixture(data: dict[str, Any]) -> None:
    missing = sorted(REQUIRED_TOP_LEVEL - set(data))
    if missing:
        fail(f"Fixture is missing required fields: {', '.join(missing)}")
    require_string(data.get("fixture_version"), "fixture_version")
    require_string(data.get("source_name"), "source_name")
    validate_provider_contract(data)
    validate_no_private_fixture_values(data)

    items = data.get("items")
    if not isinstance(items, list) or not items:
        fail("items must be a non-empty list.")

    seen_ids: set[str] = set()
    seen_source_kinds: set[str] = set()
    for index, raw_item in enumerate(items):
        item = require_mapping(raw_item, f"items[{index}]")
        missing_item = sorted(REQUIRED_ITEM_FIELDS - set(item))
        if missing_item:
            fail(f"items[{index}] is missing required fields: {', '.join(missing_item)}")
        item_id = require_string(item["item_id"], f"items[{index}].item_id")
        if item_id in seen_ids:
            fail(f"items[{index}].item_id must be unique: {item_id}")
        seen_ids.add(item_id)
        source_kind = require_string(item["source_kind"], f"items[{index}].source_kind")
        if source_kind not in ALLOWED_SOURCE_KINDS:
            fail(f"items[{index}].source_kind is unsupported: {source_kind}")
        seen_source_kinds.add(source_kind)
        for field in ("source", "received_at", "company", "role", "description"):
            require_string(item[field], f"items[{index}].{field}")
        contact = require_string(item["contact"], f"items[{index}].contact")
        contact_domain = contact.rsplit("@", 1)[-1]
        if contact_domain != "example.test" and not contact_domain.endswith(".example.test"):
            fail(f"items[{index}].contact must use example.test: {contact}")
        require_string_list(item["signals"], f"items[{index}].signals")
        require_string_list(item["risk_flags"], f"items[{index}].risk_flags")
        details = require_optional_details(item, f"items[{index}]")
        for key, value in details.items():
            require_string(str(key), f"items[{index}].details key")
            if isinstance(value, bool):
                continue
            require_string(value, f"items[{index}].details.{key}")

    missing_source_kinds = sorted(REQUIRED_SOURCE_KINDS - seen_source_kinds)
    if missing_source_kinds:
        fail(f"Fixture is missing required fake intake inputs: {', '.join(missing_source_kinds)}")


def provider_status(mode: str) -> ProviderStatus:
    if mode == "fake":
        return ProviderStatus(
            name="fake-deterministic",
            note="No local model required; no network calls are made.",
        )

    for command in ("ollama", "llama-cli", "llama-server"):
        if shutil.which(command):
            return ProviderStatus(
                name="fake-deterministic",
                note=(
                    f"Detected local provider command `{command}`, but model calls are "
                    "disabled in this scaffold; deterministic fake provider used."
                ),
            )
    return ProviderStatus(
        name="fake-deterministic",
        note="No supported local provider command found; skipped cleanly.",
    )


def item_details(item: dict[str, Any]) -> dict[str, Any]:
    return require_mapping(item.get("details", {}), "details")


def missing_fields_for_item(item: dict[str, Any]) -> tuple[str, ...]:
    risk_flags = set(require_string_list(item["risk_flags"], "risk_flags"))
    if REJECT_RISK_FLAGS & risk_flags:
        return ()
    details = item_details(item)
    required_details = DETAIL_REQUIREMENTS_BY_SOURCE_KIND.get(item["source_kind"], [])
    missing = [
        f"details.{field}"
        for field in required_details
        if not str(details.get(field, "")).strip()
    ]
    return tuple(missing)


def has_reciprocal_signal(item: dict[str, Any]) -> bool:
    details = item_details(item)
    signals = set(require_string_list(item["signals"], "signals"))
    explicit_override = details.get("explicit_opportunity_override") is True
    return bool(signals & RECIPROCAL_SIGNALS) or explicit_override


def classify_item(item: dict[str, Any]) -> tuple[str, str, str, str, str, bool]:
    source_kind = require_string(item["source_kind"], "source_kind")
    signals = set(require_string_list(item["signals"], "signals"))
    risk_flags = set(require_string_list(item["risk_flags"], "risk_flags"))
    missing_fields = missing_fields_for_item(item)

    if REJECT_RISK_FLAGS & risk_flags:
        return (
            "Reject",
            "reject",
            "lead",
            "no_crm_write",
            "Do not pursue; keep only the read-only fixture summary.",
            False,
        )
    if source_kind == "application_confirmation":
        return (
            "Lead",
            "lead",
            "lead",
            "update_lead_application_confirmed",
            "Update the matching Lead with confirmation evidence after approval.",
            True,
        )
    if source_kind == "client_inquiry" and missing_fields:
        return (
            "Needs more info",
            "needs_more_info",
            "lead",
            "create_lead_and_clarification_task",
            (
                "Ask for the missing consulting intake details before treating "
                "this as an Opportunity."
            ),
            True,
        )
    if has_reciprocal_signal(item):
        return (
            "Opportunity candidate",
            "opportunity_candidate",
            "opportunity_candidate",
            "prepare_opportunity_after_approval",
            "Prepare follow-up and require human approval before any outreach or CRM write.",
            True,
        )
    if "remote" in signals and ({"automation", "platform", "consulting"} & signals):
        return (
            "Lead",
            "lead",
            "lead",
            "create_priority_lead",
            "Draft a tailored application packet for human review.",
            True,
        )
    return (
        "Needs more info",
        "needs_more_info",
        "lead",
        "create_lead_and_clarification_task",
        "Add to the review queue and clarify missing fit or next-step details.",
        True,
    )


def build_lead_fields(item: dict[str, Any], status: str) -> dict[str, str]:
    return {
        "name": f"{item['role']} - {item['company']}",
        "accountName": item["company"],
        "emailAddress": item["contact"],
        "title": item["role"],
        "status": status,
        "source": item["source"],
        "description": item["description"],
    }


def build_dry_run_change_set(
    item: dict[str, Any],
    recommendation_slug: str,
    recommended_crm_action: str,
    approval_required: bool,
    source_attribution: str,
    audit_note: str,
    missing_fields: tuple[str, ...],
) -> dict[str, Any] | None:
    if recommendation_slug == "reject":
        return None

    changes: list[dict[str, Any]] = []
    if recommended_crm_action == "update_lead_application_confirmed":
        changes.append(
            {
                "change_id": f"{item['item_id']}-lead-confirmation",
                "action": "update",
                "entity": "Lead",
                "match": {
                    "company": item["company"],
                    "role": item["role"],
                },
                "fields": {
                    "status": "In Process",
                    "description": (
                        f"{item['description']}\n\n"
                        f"Application confirmation source: {source_attribution}"
                    ),
                },
            }
        )
    elif recommendation_slug == "opportunity_candidate":
        changes.append(
            {
                "change_id": f"{item['item_id']}-opportunity",
                "action": "create",
                "entity": "Opportunity",
                "fields": {
                    "name": f"{item['role']} - {item['company']}",
                    "accountName": item["company"],
                    "stage": "Qualification",
                    "probability": "25",
                    "description": (
                        f"{item['description']}\n\n"
                        f"Reciprocal signal present. Source: {source_attribution}"
                    ),
                },
            }
        )
    else:
        status = "New" if recommendation_slug == "lead" else "Assigned"
        changes.append(
            {
                "change_id": f"{item['item_id']}-lead",
                "action": "create",
                "entity": "Lead",
                "fields": build_lead_fields(item, status),
            }
        )

    if missing_fields:
        changes.append(
            {
                "change_id": f"{item['item_id']}-clarification-task",
                "action": "create",
                "entity": "Task",
                "fields": {
                    "name": f"Clarify intake details for {item['company']}",
                    "status": "Not Started",
                    "priority": "Normal",
                    "parentType": "Lead",
                    "parentName": f"{item['role']} - {item['company']}",
                    "description": f"Missing fields: {', '.join(missing_fields)}",
                },
            }
        )

    return {
        "change_set_id": f"dryrun-{item['item_id']}",
        "source_item_id": item["item_id"],
        "dry_run": True,
        "approval_required": approval_required,
        "write_performed": False,
        "source_attribution": source_attribution,
        "audit_note": audit_note,
        "changes": changes,
    }


def run_automation(data: dict[str, Any]) -> list[AutomationResult]:
    results: list[AutomationResult] = []
    for item in data["items"]:
        (
            recommendation,
            recommendation_slug,
            crm_classification,
            recommended_crm_action,
            next_action,
            approval_required,
        ) = classify_item(item)
        summary = (
            f"{item['company']} - {item['role']}: "
            f"{item['description']}"
        )
        details = item_details(item)
        attribution_parts = [
            f"{item['source_kind']} from {item['source']}",
            f"received {item['received_at']}",
            f"via {item['contact']}",
        ]
        if details.get("source_subject"):
            attribution_parts.append(f"subject {details['source_subject']}")
        if details.get("source_url"):
            attribution_parts.append(f"url {details['source_url']}")
        source_attribution = "; ".join(attribution_parts)
        missing_fields = missing_fields_for_item(item)
        audit_note = (
            "Assistant-originated dry run; no CRM write performed. "
            f"Source item {item['item_id']} attributed to {source_attribution}."
        )
        dry_run_change_set = build_dry_run_change_set(
            item,
            recommendation_slug,
            recommended_crm_action,
            approval_required,
            source_attribution,
            audit_note,
            missing_fields,
        )
        results.append(
            AutomationResult(
                item_id=item["item_id"],
                source_kind=item["source_kind"],
                source=item["source"],
                company=item["company"],
                role=item["role"],
                recommendation=recommendation,
                recommendation_slug=recommendation_slug,
                crm_classification=crm_classification,
                recommended_crm_action=recommended_crm_action,
                summary=summary,
                next_action=next_action,
                approval_required=approval_required,
                source_attribution=source_attribution,
                audit_note=audit_note,
                missing_fields=missing_fields,
                dry_run_change_set=dry_run_change_set,
            )
        )
    return results


def render_markdown(
    fixture: dict[str, Any],
    results: list[AutomationResult],
    provider: ProviderStatus,
) -> str:
    lines = [
        "# Automation Fixture Report",
        "",
        f"- Fixture source: {fixture['source_name']}",
        f"- Provider: {provider.name}",
        f"- Provider note: {provider.note}",
        "- Hosted API key required: no",
        "- Network calls by default: no",
        "- Writes performed: no",
        "",
    ]

    for result in results:
        approval = "yes" if result.approval_required else "no"
        missing = ", ".join(result.missing_fields) if result.missing_fields else "none"
        change_set = (
            result.dry_run_change_set["change_set_id"]
            if result.dry_run_change_set is not None
            else "none"
        )
        lines.extend(
            [
                f"## {result.item_id}",
                "",
                f"- Source kind: {result.source_kind}",
                f"- Source: {result.source}",
                f"- Source attribution: {result.source_attribution}",
                f"- Company: {result.company}",
                f"- Role: {result.role}",
                f"- Recommendation: {result.recommendation}",
                f"- Lead vs opportunity: {result.crm_classification}",
                f"- Recommended CRM action: {result.recommended_crm_action}",
                f"- Approval required: {approval}",
                f"- Missing fields: {missing}",
                f"- Dry-run change set: {change_set}",
                f"- Audit note: {result.audit_note}",
                f"- Summary: {result.summary}",
                f"- Next action: {result.next_action}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def render_dry_run_json(
    fixture: dict[str, Any],
    results: list[AutomationResult],
    provider: ProviderStatus,
) -> dict[str, Any]:
    return {
        "fixture_source": fixture["source_name"],
        "provider": provider.name,
        "network_calls_by_default": False,
        "write_performed": False,
        "items": [
            {
                "item_id": result.item_id,
                "source_kind": result.source_kind,
                "source": result.source,
                "company": result.company,
                "role": result.role,
                "recommendation": result.recommendation,
                "recommendation_slug": result.recommendation_slug,
                "crm_classification": result.crm_classification,
                "recommended_crm_action": result.recommended_crm_action,
                "approval_required": result.approval_required,
                "missing_fields": list(result.missing_fields),
                "source_attribution": result.source_attribution,
                "audit_note": result.audit_note,
                "dry_run_change_set_id": (
                    result.dry_run_change_set["change_set_id"]
                    if result.dry_run_change_set is not None
                    else None
                ),
            }
            for result in results
        ],
        "dry_run_change_sets": [
            result.dry_run_change_set
            for result in results
            if result.dry_run_change_set is not None
        ],
    }


def run_self_test(valid_data: dict[str, Any]) -> None:
    missing_field = copy.deepcopy(valid_data)
    del missing_field["items"][0]["role"]
    try:
        validate_fixture(missing_field)
    except FixtureError:
        pass
    else:
        fail("Self-test failed: fixture with missing required item field passed.")

    missing_required_kind = copy.deepcopy(valid_data)
    missing_required_kind["items"] = [
        item
        for item in missing_required_kind["items"]
        if item["source_kind"] != "client_inquiry"
    ]
    try:
        validate_fixture(missing_required_kind)
    except FixtureError:
        pass
    else:
        fail("Self-test failed: fixture missing client inquiry input passed.")

    no_reciprocal = copy.deepcopy(valid_data)
    for item in no_reciprocal["items"]:
        if item["source_kind"] == "recruiter_email":
            item["signals"] = ["remote", "automation"]
            item["details"].pop("reciprocal_signal_detail", None)
            recommendation = classify_item(item)[1]
            if recommendation == "opportunity_candidate":
                fail("Self-test failed: Opportunity candidate did not require reciprocal signal.")

    provider = provider_status("fake")
    results = run_automation(valid_data)
    dry_run = render_dry_run_json(valid_data, results, provider)
    rejected = [item for item in dry_run["items"] if item["recommendation_slug"] == "reject"]
    if not rejected:
        fail("Self-test failed: no rejected fixture item was exercised.")
    if any(item["dry_run_change_set_id"] is not None for item in rejected):
        fail("Self-test failed: rejected fixture generated a CRM payload.")
    if not dry_run["dry_run_change_sets"]:
        fail("Self-test failed: no dry-run CRM change sets were generated.")
    if not any(item["missing_fields"] for item in dry_run["items"]):
        fail("Self-test failed: missing fields were not surfaced.")


def run_source_export_self_test(valid_export: dict[str, Any]) -> None:
    missing_field = copy.deepcopy(valid_export)
    del missing_field["records"][0]["subject"]
    try:
        validate_source_export(missing_field)
    except FixtureError:
        pass
    else:
        fail("Self-test failed: source export missing required field passed.")

    duplicate_source = copy.deepcopy(valid_export)
    duplicate_record = copy.deepcopy(duplicate_source["records"][0])
    duplicate_record["source_record_id"] = "export-msg-duplicate"
    duplicate_record["source_name"] = "example-duplicate-job-alert"
    duplicate_source["records"].append(duplicate_record)
    converted = source_export_to_fixture(duplicate_source)
    duplicates = [
        item
        for item in converted["items"]
        if item.get("details", {}).get("possible_duplicate_of")
    ]
    if not duplicates:
        fail("Self-test failed: duplicate-ish source record was not detected.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fixture",
        type=Path,
        default=DEFAULT_FIXTURE,
        help="Path to a fake automation fixture JSON file.",
    )
    parser.add_argument(
        "--source-export",
        type=Path,
        help=(
            "Path to a fake redacted source export JSON file. "
            "When set, it is adapted into the triage fixture model."
        ),
    )
    parser.add_argument(
        "--provider",
        choices=("fake", "local-auto"),
        default="fake",
        help="Provider mode. local-auto detects local CLIs but still runs deterministically.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional Markdown output path. Defaults to stdout.",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        help="Optional machine-readable dry-run JSON output path.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Also verify that a fixture missing required fields fails validation.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.source_export:
            source_export = load_source_export(args.source_export)
            if args.self_test:
                run_source_export_self_test(source_export)
            fixture = source_export_to_fixture(source_export)
        else:
            fixture = load_fixture(args.fixture)
        validate_fixture(fixture)
        if args.self_test:
            run_self_test(fixture)
        provider = provider_status(args.provider)
        results = run_automation(fixture)
        markdown = render_markdown(fixture, results, provider)
        dry_run_json = render_dry_run_json(fixture, results, provider)
    except FixtureError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc

    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(
            json.dumps(dry_run_json, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(markdown, encoding="utf-8")
    else:
        print(markdown, end="")


if __name__ == "__main__":
    main()
