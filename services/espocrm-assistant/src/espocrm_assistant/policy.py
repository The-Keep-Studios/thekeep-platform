from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import uuid
from datetime import UTC, datetime
from typing import Any

READ_FIELDS = {
    "Lead": {
        "id", "name", "firstName", "lastName", "accountName", "emailAddress",
        "phoneNumber", "title", "website", "status", "source", "description",
        "createdAt", "modifiedAt", "assignedUserId",
    },
    "Opportunity": {
        "id", "name", "amount", "amountCurrency", "stage", "probability",
        "closeDate", "accountId", "contactsIds", "leadSource", "description",
        "createdAt", "modifiedAt", "assignedUserId",
    },
    "Account": {
        "id", "name", "website", "emailAddress", "phoneNumber", "type",
        "industry", "description", "createdAt", "modifiedAt", "assignedUserId",
    },
    "Contact": {
        "id", "name", "firstName", "lastName", "emailAddress", "phoneNumber",
        "accountId", "title", "description", "createdAt", "modifiedAt",
        "assignedUserId",
    },
    "Email": {
        "id", "name", "subject", "from", "to", "cc", "dateSent", "status",
        "parentId", "parentType", "bodyPlain", "createdAt", "modifiedAt",
    },
    "Task": {
        "id", "name", "status", "priority", "dateStart", "dateEnd",
        "description", "parentType", "parentId", "createdAt", "modifiedAt",
        "assignedUserId",
    },
}

WRITE_FIELDS = {
    "Lead": {
        "firstName", "lastName", "name", "accountName", "emailAddress",
        "emailAddressData", "phoneNumber", "phoneNumberData", "title", "website",
        "addressStreet", "addressCity", "addressState", "addressCountry",
        "addressPostalCode", "status", "source", "opportunityAmount",
        "opportunityAmountCurrency", "campaignId", "industry", "description",
        "assignedUserId", "teamsIds",
    },
    "Opportunity": {
        "name", "amount", "amountCurrency", "stage", "probability", "closeDate",
        "accountId", "contactsIds", "description", "assignedUserId", "teamsIds",
        "leadSource",
    },
    "Task": {
        "name", "status", "priority", "dateStart", "dateEnd", "dateStartDate",
        "dateEndDate", "description", "parentType", "parentId", "assignedUserId",
        "teamsIds",
    },
}

SOURCE_TYPES = {
    "AI Scrape", "Email Recruiter", "LinkedIn", "Slack/Community",
    "Personal Network", "Direct Company Search", "Manual/Ian Found",
    "Trello Import", "Unknown",
}
FILTER_TYPES = {
    "equals", "notEquals", "contains", "startsWith", "isNull", "isNotNull",
    "in", "notIn", "greaterThan", "lessThan", "between",
}
_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_CHANGE_KEYS = {
    "schemaVersion", "changeId", "createdAt", "operation", "entity", "recordId",
    "fields", "source", "policy", "precondition", "duplicateCandidates",
    "auditNote", "sha256",
}


class PolicyError(ValueError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def change_hash(change: dict[str, Any]) -> str:
    unsigned = {key: value for key, value in change.items() if key != "sha256"}
    return hashlib.sha256(canonical_json(unsigned).encode()).hexdigest()


def validate_record_id(value: str) -> None:
    if not _ID.fullmatch(value):
        raise PolicyError("invalid record ID")


def validate_filters(entity: str, filters: list[dict[str, Any]]) -> None:
    if entity not in READ_FIELDS:
        raise PolicyError("entity is not readable")
    if len(filters) > 8:
        raise PolicyError("at most eight filters are allowed")
    for item in filters:
        if item.get("type") not in FILTER_TYPES:
            raise PolicyError("filter type is not allowed")
        if item.get("attribute") not in READ_FIELDS[entity]:
            raise PolicyError("filter field is not allowed")
        if len(canonical_json(item.get("value"))) > 500:
            raise PolicyError("filter value is too large")


def prepare_change(
    *,
    operation: str,
    entity: str,
    fields: dict[str, Any],
    source: dict[str, Any],
    record_id: str | None = None,
    expected_modified_at: str | None = None,
    reciprocal_signal: str | None = None,
    opportunity_override: str | None = None,
    duplicate_candidates: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    if operation not in {"create", "update"}:
        raise PolicyError("only create and update operations are allowed")
    if entity not in WRITE_FIELDS:
        raise PolicyError("entity is not writable")
    if not isinstance(fields, dict) or not fields or set(fields) - WRITE_FIELDS[entity]:
        raise PolicyError("fields contain an empty or disallowed write")
    if len(canonical_json(fields)) > 100_000:
        raise PolicyError("write payload is too large")
    if not isinstance(source, dict) or source.get("type") not in SOURCE_TYPES:
        raise PolicyError("source type and reference are required")
    if not str(source.get("reference", "")).strip() or len(str(source["reference"])) > 2_000:
        raise PolicyError("source type and reference are required")

    if operation == "update":
        if not record_id or not expected_modified_at:
            raise PolicyError("updates require record ID and modifiedAt precondition")
        validate_record_id(record_id)
    elif record_id or expected_modified_at:
        raise PolicyError("create cannot include update preconditions")

    if entity == "Opportunity" and not (
        str(reciprocal_signal or "").strip() or str(opportunity_override or "").strip()
    ):
        raise PolicyError("Opportunity writes require reciprocal signal or explicit override")
    if operation == "create" and entity == "Opportunity" and not fields.get("name"):
        raise PolicyError("Opportunity creates require a name")
    if operation == "create" and entity == "Lead" and not any(
        fields.get(key) for key in ("name", "firstName", "lastName", "emailAddress", "accountName", "website")
    ):
        raise PolicyError("Lead creates require identifying fields")
    if entity == "Task":
        if operation != "create":
            raise PolicyError("Task updates are not exposed")
        if fields.get("parentType") not in {"Lead", "Opportunity"} or not fields.get("parentId"):
            raise PolicyError("Task must link to a Lead or Opportunity")
        validate_record_id(str(fields["parentId"]))

    change = {
        "schemaVersion": 1,
        "changeId": str(uuid.uuid4()),
        "createdAt": datetime.now(UTC).isoformat(),
        "operation": operation,
        "entity": entity,
        "recordId": record_id,
        "fields": fields,
        "source": source,
        "policy": {
            "reciprocalSignal": reciprocal_signal,
            "explicitOpportunityOverride": opportunity_override,
        },
        "precondition": {"modifiedAt": expected_modified_at},
        "duplicateCandidates": duplicate_candidates or [],
        "auditNote": f"Prepared by The Keep assistant from {source['type']}: {source['reference']}",
    }
    change["sha256"] = change_hash(change)
    return change


def validate_change(change: dict[str, Any]) -> None:
    if set(change) != _CHANGE_KEYS or change.get("schemaVersion") != 1:
        raise PolicyError("change-set shape is invalid")
    if change.get("sha256") != change_hash(change):
        raise PolicyError("change-set hash is invalid")
    try:
        uuid.UUID(change["changeId"])
        created_at = datetime.fromisoformat(change["createdAt"])
        if created_at.tzinfo is None:
            raise ValueError("createdAt requires timezone")
        expected = prepare_change(
            operation=change["operation"],
            entity=change["entity"],
            fields=change["fields"],
            source=change["source"],
            record_id=change["recordId"],
            expected_modified_at=change["precondition"]["modifiedAt"],
            reciprocal_signal=change["policy"]["reciprocalSignal"],
            opportunity_override=change["policy"]["explicitOpportunityOverride"],
            duplicate_candidates=change["duplicateCandidates"],
        )
    except (AttributeError, KeyError, TypeError, ValueError) as error:
        raise PolicyError("change-set content is invalid") from error
    for key in (
        "operation", "entity", "recordId", "fields", "source", "policy",
        "precondition", "duplicateCandidates", "auditNote",
    ):
        if change.get(key) != expected.get(key):
            raise PolicyError("change-set content is invalid")


def export_csv(changes: list[dict[str, Any]]) -> str:
    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=[
            "operation", "entity", "recordId", "sha256", "sourceType",
            "sourceReference", "fieldsJson",
        ],
    )
    writer.writeheader()
    for change in changes:
        validate_change(change)
        writer.writerow({
            "operation": change["operation"],
            "entity": change["entity"],
            "recordId": change["recordId"] or "",
            "sha256": change["sha256"],
            "sourceType": change["source"]["type"],
            "sourceReference": change["source"]["reference"],
            "fieldsJson": canonical_json(change["fields"]),
        })
    return output.getvalue()
