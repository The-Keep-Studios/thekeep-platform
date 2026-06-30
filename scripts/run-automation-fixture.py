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
    "source",
    "received_at",
    "company",
    "role",
    "description",
    "contact",
    "signals",
    "risk_flags",
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


class FixtureError(ValueError):
    """Raised for invalid fake automation fixtures."""


@dataclass(frozen=True)
class ProviderStatus:
    name: str
    note: str


@dataclass(frozen=True)
class AutomationResult:
    item_id: str
    source: str
    company: str
    role: str
    classification: str
    summary: str
    next_action: str
    approval_needed: bool


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
            fail(f"Fixture must not contain service URLs: {value}")
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
    for index, raw_item in enumerate(items):
        item = require_mapping(raw_item, f"items[{index}]")
        missing_item = sorted(REQUIRED_ITEM_FIELDS - set(item))
        if missing_item:
            fail(f"items[{index}] is missing required fields: {', '.join(missing_item)}")
        item_id = require_string(item["item_id"], f"items[{index}].item_id")
        if item_id in seen_ids:
            fail(f"items[{index}].item_id must be unique: {item_id}")
        seen_ids.add(item_id)
        for field in ("source", "received_at", "company", "role", "description"):
            require_string(item[field], f"items[{index}].{field}")
        contact = require_string(item["contact"], f"items[{index}].contact")
        contact_domain = contact.rsplit("@", 1)[-1]
        if contact_domain != "example.test" and not contact_domain.endswith(".example.test"):
            fail(f"items[{index}].contact must use example.test: {contact}")
        require_string_list(item["signals"], f"items[{index}].signals")
        require_string_list(item["risk_flags"], f"items[{index}].risk_flags")


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


def classify_item(item: dict[str, Any]) -> tuple[str, str, bool]:
    signals = set(require_string_list(item["signals"], "signals"))
    risk_flags = set(require_string_list(item["risk_flags"], "risk_flags"))

    if {"onsite_only", "low_fit"} & risk_flags:
        return (
            "reject",
            "Do not pursue; keep only the read-only fixture summary.",
            False,
        )
    if "human_reply" in signals:
        return (
            "opportunity_candidate",
            "Prepare follow-up questions and require human approval before any outreach or CRM write.",
            True,
        )
    if "remote" in signals and ({"automation", "platform", "consulting"} & signals):
        return (
            "priority_lead",
            "Draft a tailored application packet for human review.",
            True,
        )
    return (
        "lead",
        "Add to the review queue and wait for human prioritization.",
        True,
    )


def run_automation(data: dict[str, Any]) -> list[AutomationResult]:
    results: list[AutomationResult] = []
    for item in data["items"]:
        classification, next_action, approval_needed = classify_item(item)
        summary = (
            f"{item['company']} - {item['role']}: "
            f"{item['description']}"
        )
        results.append(
            AutomationResult(
                item_id=item["item_id"],
                source=item["source"],
                company=item["company"],
                role=item["role"],
                classification=classification,
                summary=summary,
                next_action=next_action,
                approval_needed=approval_needed,
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
        approval = "yes" if result.approval_needed else "no"
        lines.extend(
            [
                f"## {result.item_id}",
                "",
                f"- Source: {result.source}",
                f"- Company: {result.company}",
                f"- Role: {result.role}",
                f"- Classification: {result.classification}",
                f"- Summary: {result.summary}",
                f"- Next action: {result.next_action}",
                f"- Approval needed: {approval}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def run_self_test(valid_data: dict[str, Any]) -> None:
    missing_field = copy.deepcopy(valid_data)
    del missing_field["items"][0]["role"]
    try:
        validate_fixture(missing_field)
    except FixtureError:
        return
    fail("Self-test failed: fixture with missing required item field passed.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fixture",
        type=Path,
        default=DEFAULT_FIXTURE,
        help="Path to a fake automation fixture JSON file.",
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
        "--self-test",
        action="store_true",
        help="Also verify that a fixture missing required fields fails validation.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        fixture = load_fixture(args.fixture)
        validate_fixture(fixture)
        if args.self_test:
            run_self_test(fixture)
        provider = provider_status(args.provider)
        markdown = render_markdown(fixture, run_automation(fixture), provider)
    except FixtureError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc

    if args.output:
        args.output.write_text(markdown, encoding="utf-8")
    else:
        print(markdown, end="")


if __name__ == "__main__":
    main()
