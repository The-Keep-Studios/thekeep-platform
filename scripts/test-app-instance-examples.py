#!/usr/bin/env python3
"""Validate safe fake app-instance examples."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_PATH = PROJECT_ROOT / "examples" / "app-instances.example.json"
DOC_PATH = PROJECT_ROOT / "README.md"

REQUIRED_FIELDS = {
    "app_type",
    "instance_name",
    "namespace",
    "hostname",
    "access_policy",
    "exposure",
    "storage",
    "secrets",
    "backups",
}
ALLOWED_APP_TYPES = {"baserow", "postiz", "mixpost", "dmarc-monitor"}
ALLOWED_ACCESS_POLICIES = {
    "internal-only",
    "internal-authenticated",
    "public-readonly",
}
DNS_LABEL = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
BANNED_PUBLIC_STRINGS = {
    "thekeepstudios.com",
    "gmail.com",
    "mailgun",
    "changeme",
    "change_me",
    "replace_me",
}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def require_mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{context} must be a mapping.")
    return value


def require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} must be a non-empty string.")
    return value


def require_dns_label(value: str, context: str) -> None:
    if len(value) > 63 or not DNS_LABEL.match(value):
        fail(f"{context} must be a DNS-safe label: {value}")


def require_unique(seen: set[str], value: str, context: str) -> None:
    if value in seen:
        fail(f"{context} must be unique: {value}")
    seen.add(value)


def load_example() -> dict[str, Any]:
    if not EXAMPLE_PATH.exists():
        fail(f"Missing app-instance example: {EXAMPLE_PATH}")

    raw = EXAMPLE_PATH.read_text(encoding="utf-8")
    lower_raw = raw.lower()
    for banned in BANNED_PUBLIC_STRINGS:
        if banned in lower_raw:
            fail(f"Example contains banned public/private value: {banned}")

    try:
        loaded = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"{EXAMPLE_PATH} is not valid JSON: {exc}")
    return require_mapping(loaded, str(EXAMPLE_PATH))


def validate_instance(index: int, instance: Any, seen: dict[str, set[str]]) -> None:
    item = require_mapping(instance, f"app_instances[{index}]")
    missing = sorted(REQUIRED_FIELDS - set(item))
    if missing:
        fail(f"app_instances[{index}] is missing required fields: {', '.join(missing)}")

    app_type = require_string(item["app_type"], f"app_instances[{index}].app_type")
    if app_type not in ALLOWED_APP_TYPES:
        fail(f"app_instances[{index}].app_type is unsupported: {app_type}")

    instance_name = require_string(
        item["instance_name"], f"app_instances[{index}].instance_name"
    )
    namespace = require_string(item["namespace"], f"app_instances[{index}].namespace")
    hostname = require_string(item["hostname"], f"app_instances[{index}].hostname")
    access_policy = require_string(
        item["access_policy"], f"app_instances[{index}].access_policy"
    )

    require_dns_label(instance_name, f"app_instances[{index}].instance_name")
    require_dns_label(namespace, f"app_instances[{index}].namespace")
    require_unique(seen["instance_names"], instance_name, "instance_name")
    require_unique(seen["namespaces"], namespace, "namespace")
    require_unique(seen["hostnames"], hostname, "hostname")

    if namespace != instance_name:
        fail(f"app_instances[{index}].namespace must match instance_name.")
    if not hostname.endswith(".invalid"):
        fail(f"app_instances[{index}].hostname must use the .invalid TLD.")
    if access_policy not in ALLOWED_ACCESS_POLICIES:
        fail(f"app_instances[{index}].access_policy is unsupported: {access_policy}")

    exposure = require_mapping(item["exposure"], f"app_instances[{index}].exposure")
    for field in ("public_ingress", "cloudflare_tunnel_route"):
        if not isinstance(exposure.get(field), bool):
            fail(f"app_instances[{index}].exposure.{field} must be boolean.")

    storage = require_mapping(item["storage"], f"app_instances[{index}].storage")
    for field in ("pvc_prefix", "database_binding"):
        value = require_string(
            storage.get(field),
            f"app_instances[{index}].storage.{field}",
        )
        require_dns_label(value, f"app_instances[{index}].storage.{field}")
        if not value.startswith(instance_name):
            fail(
                f"app_instances[{index}].storage.{field} "
                "must start with instance_name."
            )
        require_unique(seen[field], value, field)

    secrets = require_mapping(item["secrets"], f"app_instances[{index}].secrets")
    if not secrets:
        fail(f"app_instances[{index}].secrets must not be empty.")
    for key, value in secrets.items():
        if not str(key).endswith("_ref"):
            fail(f"app_instances[{index}].secrets.{key} must be a reference key.")
        secret_ref = require_string(value, f"app_instances[{index}].secrets.{key}")
        require_dns_label(secret_ref, f"app_instances[{index}].secrets.{key}")
        if not secret_ref.startswith(instance_name):
            fail(f"app_instances[{index}].secrets.{key} must start with instance_name.")
        require_unique(seen["secret_refs"], secret_ref, "secret_ref")

    backups = require_mapping(item["backups"], f"app_instances[{index}].backups")
    if not isinstance(backups.get("enabled"), bool):
        fail(f"app_instances[{index}].backups.enabled must be boolean.")
    schedule = require_string(
        backups.get("schedule"), f"app_instances[{index}].backups.schedule"
    )
    if len(schedule.split()) != 5:
        fail(f"app_instances[{index}].backups.schedule must be a cron expression.")
    retention = require_string(
        backups.get("retention"), f"app_instances[{index}].backups.retention"
    )
    if not re.match(r"^[0-9]+[dhmw]$", retention):
        fail(f"app_instances[{index}].backups.retention must look like 14d.")


def validate_doc_links() -> None:
    doc = DOC_PATH.read_text(encoding="utf-8")
    for required in (
        "examples/app-instances.example.json",
        "scripts/test-app-instance-examples.py",
    ):
        if required not in doc:
            fail(f"{DOC_PATH} must reference {required}.")


def main() -> None:
    data = load_example()
    instances = data.get("app_instances")
    if not isinstance(instances, list) or not instances:
        fail("app_instances must be a non-empty list.")

    seen: dict[str, set[str]] = {
        "instance_names": set(),
        "namespaces": set(),
        "hostnames": set(),
        "pvc_prefix": set(),
        "database_binding": set(),
        "secret_refs": set(),
    }
    for index, instance in enumerate(instances):
        validate_instance(index, instance, seen)

    validate_doc_links()
    print(f"Validated {len(instances)} fake app-instance example(s).")


if __name__ == "__main__":
    main()
