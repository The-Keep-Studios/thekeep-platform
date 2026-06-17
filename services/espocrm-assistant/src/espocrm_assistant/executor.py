from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .client import EspoClient
from .policy import PolicyError, validate_change
from .service import EspoAssistant


def _append_audit(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, (json.dumps(report, sort_keys=True) + "\n").encode())
    finally:
        os.close(descriptor)
    os.chmod(path, 0o600)


def apply_change(
    client: EspoClient,
    change: dict[str, Any],
    *,
    approved_sha256: str,
    approved_by: str,
    audit_log: Path,
) -> dict[str, Any]:
    validate_change(change)
    if change["sha256"] != approved_sha256:
        raise PolicyError("approved hash does not match change set")
    if not approved_by.strip() or len(approved_by) > 200 or "\n" in approved_by:
        raise PolicyError("approver identity is required")

    report = {
        "status": "pending",
        "changeId": change["changeId"],
        "sha256": change["sha256"],
        "entity": change["entity"],
        "recordId": change.get("recordId"),
        "approvedBy": approved_by,
        "appliedAt": datetime.now(UTC).isoformat(),
        "source": change["source"],
        "before": None,
        "after": None,
        "auditNoteId": None,
    }
    _append_audit(audit_log, report)
    wrote = False
    try:
        if change["operation"] == "update":
            before = client.get(change["entity"], change["recordId"])
            report["before"] = before
            if before.get("modifiedAt") != change["precondition"]["modifiedAt"]:
                raise PolicyError("record changed after the change set was prepared")
            client.update(change["entity"], change["recordId"], change["fields"])
            record_id = change["recordId"]
        else:
            if change["entity"] in {"Lead", "Opportunity", "Account", "Contact"}:
                current = EspoAssistant(client).duplicate_candidates(change["fields"])
                approved = {
                    (item.get("entity"), item.get("id"))
                    for item in change["duplicateCandidates"]
                }
                if any((item["entity"], item["id"]) not in approved for item in current):
                    raise PolicyError("new duplicate candidate appeared after approval")
            result = client.create(change["entity"], change["fields"])
            record_id = result.get("id")
            if not record_id:
                raise RuntimeError("EspoCRM create response did not include an ID")
            report["recordId"] = record_id
        wrote = True

        report["after"] = client.get(change["entity"], record_id)
        note = client.create("Note", {
            "type": "Post",
            "parentType": change["entity"],
            "parentId": record_id,
            "post": (
                f"{change['auditNote']}\n"
                f"Approved by {approved_by}; change {change['changeId']}; "
                f"sha256 {change['sha256']}."
            ),
        })
        report["auditNoteId"] = note.get("id")
        report["status"] = "applied"
    except Exception as error:
        report["status"] = "partial" if wrote else "failed"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        _append_audit(audit_log, report)
    return report
