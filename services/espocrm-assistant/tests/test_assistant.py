from __future__ import annotations

import base64
import hashlib
import hmac
import json
import tempfile
import unittest
from pathlib import Path

from espocrm_assistant.client import EspoClient
from espocrm_assistant.executor import apply_change
from espocrm_assistant.http_server import dispatch
from espocrm_assistant.policy import PolicyError, export_csv, prepare_change
from espocrm_assistant.service import EspoAssistant


def source(kind: str = "LinkedIn") -> dict[str, str]:
    return {"type": kind, "reference": "https://example.test/source/1"}


class FakeClient:
    def __init__(self) -> None:
        self.records = {}
        self.created = []

    def get(self, entity, record_id):
        return self.records[(entity, record_id)].copy()

    def create(self, entity, fields):
        record_id = f"id-{len(self.created) + 1}"
        record = {"id": record_id, "modifiedAt": "2026-06-11 12:00:00", **fields}
        self.created.append((entity, fields.copy()))
        self.records[(entity, record_id)] = record
        return record.copy()

    def update(self, entity, record_id, fields):
        self.records[(entity, record_id)].update(fields)
        return self.records[(entity, record_id)].copy()

    def search(self, entity, params):
        where = params["where"][0]
        needle = str(where["value"]).lower()
        found = []
        for (record_entity, _), record in self.records.items():
            value = str(record.get(where["attribute"], "")).lower()
            if record_entity == entity and (
                value == needle if where["type"] == "equals" else needle in value
            ):
                found.append(record.copy())
        return {"total": len(found), "list": found[:params["maxSize"]]}


class ClientTests(unittest.TestCase):
    def test_https_is_required(self):
        with self.assertRaisesRegex(ValueError, "HTTPS"):
            EspoClient("http://crm.test", "key")

    def test_hmac_header_matches_espo_scheme(self):
        captured = {}

        def transport(method, url, headers, body, timeout):
            captured.update(headers)
            return 200, b"{}"

        client = EspoClient(
            "https://crm.test", "key", secret_key="secret",
            auth_method="hmac", transport=transport,
        )
        client.get("Lead", "abc")
        digest = hmac.new(b"secret", b"GET /Lead/abc", hashlib.sha256).hexdigest()
        expected = base64.b64encode(f"key:{digest}".encode()).decode()
        self.assertEqual(expected, captured["X-Hmac-Authorization"])
        self.assertNotIn("X-Api-Key", captured)


class PolicyTests(unittest.TestCase):
    def test_delete_and_disallowed_fields_are_rejected(self):
        with self.assertRaises(PolicyError):
            prepare_change(operation="delete", entity="Lead", fields={"name": "x"}, source=source())
        with self.assertRaises(PolicyError):
            prepare_change(operation="create", entity="Lead", fields={"portalUser": True}, source=source())

    def test_opportunity_requires_reciprocal_signal_or_override(self):
        with self.assertRaisesRegex(PolicyError, "reciprocal"):
            prepare_change(
                operation="create", entity="Opportunity",
                fields={"name": "Unanswered listing"}, source=source(),
            )
        change = prepare_change(
            operation="create", entity="Opportunity",
            fields={"name": "Recruiter replied"}, source=source(),
            reciprocal_signal="Recruiter requested an interview.",
        )
        self.assertEqual("Opportunity", change["entity"])

    def test_updates_require_precondition(self):
        with self.assertRaisesRegex(PolicyError, "precondition"):
            prepare_change(
                operation="update", entity="Lead", record_id="lead-1",
                fields={"status": "Dead"}, source=source(),
            )

    def test_task_must_be_linked(self):
        with self.assertRaisesRegex(PolicyError, "link"):
            prepare_change(
                operation="create", entity="Task",
                fields={"name": "Follow up"}, source=source(),
            )

    def test_csv_contains_validated_change(self):
        change = prepare_change(
            operation="create", entity="Lead",
            fields={"name": "Platform role"}, source=source(),
        )
        output = export_csv([change])
        self.assertIn(change["sha256"], output)
        self.assertIn("Platform role", output)

    def test_change_shape_and_hash_are_revalidated(self):
        change = prepare_change(
            operation="create", entity="Lead",
            fields={"name": "Platform role"}, source=source(),
        )
        change["unexpected"] = True
        change["sha256"] = hashlib.sha256(
            json.dumps(
                {key: value for key, value in change.items() if key != "sha256"},
                sort_keys=True, separators=(",", ":"),
            ).encode()
        ).hexdigest()
        with self.assertRaisesRegex(PolicyError, "shape"):
            export_csv([change])

    def test_issue_fixtures_follow_lead_opportunity_policy(self):
        fixtures = [
            ("LinkedIn batch", "Lead", {"name": "Imported role"}, {}, "LinkedIn"),
            ("ATS confirmation", "Lead", {"name": "Applied role", "status": "Assigned"}, {}, "Unknown"),
            ("Recruiter outreach", "Opportunity", {"name": "Recruiter screen"}, {"reciprocal_signal": "Recruiter replied."}, "Email Recruiter"),
            ("Rejected onsite", "Lead", {"name": "Onsite role", "status": "Dead"}, {}, "Manual/Ian Found"),
            ("Warm consulting", "Opportunity", {"name": "Consulting lead"}, {"reciprocal_signal": "Client requested scope."}, "Personal Network"),
        ]
        for label, entity, fields, policy, source_type in fixtures:
            with self.subTest(label):
                change = prepare_change(
                    operation="create", entity=entity, fields=fields,
                    source=source(source_type), **policy,
                )
                self.assertEqual(entity, change["entity"])


class ServiceTests(unittest.TestCase):
    def test_search_uses_espo_select_array(self):
        captured = {}

        class SearchClient:
            def search(self, entity, params):
                captured.update(params)
                return {"total": 0, "list": []}

        EspoAssistant(SearchClient()).search("Lead", fields=["id", "name"])
        self.assertEqual(["id", "name"], captured["select"])

    def test_duplicate_candidates_are_deduplicated(self):
        class SearchClient:
            def search(self, entity, params):
                return {"total": 1, "list": [{"id": "same", "name": "Acme", "secret": "no"}]}

        found = EspoAssistant(SearchClient()).duplicate_candidates({
            "name": "Acme", "accountName": "Acme",
        })
        self.assertEqual(len({(item["entity"], item["id"]) for item in found}), len(found))
        self.assertNotIn("secret", found[0])


class HttpDispatchTests(unittest.TestCase):
    def test_dispatch_exposes_read_and_prepare_tools_only(self):
        class Assistant:
            def __init__(self):
                self.calls = []

            def search(self, **payload):
                self.calls.append(("search", payload))
                return {"total": 0, "list": []}

            def get(self, **payload):
                self.calls.append(("get", payload))
                return {"id": payload["record_id"]}

            def metadata(self, **payload):
                self.calls.append(("metadata", payload))
                return {}

            def duplicate_candidates(self, **payload):
                self.calls.append(("duplicate", payload))
                return []

            def prepare_change(self, **payload):
                self.calls.append(("prepare", payload))
                return {"sha256": "abc"}

            def export_csv(self, changes):
                self.calls.append(("export", changes))
                return "operation,entity\n"

        assistant = Assistant()
        self.assertEqual({"total": 0, "list": []}, dispatch(assistant, "/crm/search", {"entity": "Lead"}))
        self.assertEqual({"csv": "operation,entity\n"}, dispatch(assistant, "/crm/export-csv", {"changes": []}))
        with self.assertRaises(KeyError):
            dispatch(assistant, "/crm/apply", {})


class ExecutorTests(unittest.TestCase):
    def test_stale_update_is_not_written(self):
        client = FakeClient()
        client.records[("Lead", "lead-1")] = {"id": "lead-1", "modifiedAt": "new"}
        change = prepare_change(
            operation="update", entity="Lead", record_id="lead-1",
            expected_modified_at="old", fields={"status": "Dead"}, source=source(),
        )
        with tempfile.TemporaryDirectory() as directory:
            report = apply_change(
                client, change, approved_sha256=change["sha256"],
                approved_by="human@example.test", audit_log=Path(directory) / "audit.jsonl",
            )
        self.assertEqual("failed", report["status"])
        self.assertEqual([], client.created)

    def test_approved_create_writes_record_note_and_private_audit(self):
        client = FakeClient()
        change = prepare_change(
            operation="create", entity="Lead",
            fields={"name": "Qualified lead"}, source=source(),
        )
        with tempfile.TemporaryDirectory() as directory:
            audit = Path(directory) / "audit.jsonl"
            report = apply_change(
                client, change, approved_sha256=change["sha256"],
                approved_by="human@example.test", audit_log=audit,
            )
            saved = [json.loads(line) for line in audit.read_text().splitlines()]
            self.assertEqual(0o600, audit.stat().st_mode & 0o777)
        self.assertEqual("applied", report["status"])
        self.assertEqual(["Lead", "Note"], [entity for entity, _ in client.created])
        self.assertEqual(["pending", "applied"], [entry["status"] for entry in saved])
        self.assertEqual(change["sha256"], saved[-1]["sha256"])

    def test_new_duplicate_blocks_create(self):
        client = FakeClient()
        change = prepare_change(
            operation="create", entity="Lead",
            fields={"name": "Qualified lead"}, source=source(),
        )
        client.records[("Lead", "lead-existing")] = {
            "id": "lead-existing", "name": "Qualified lead", "modifiedAt": "now",
        }
        with tempfile.TemporaryDirectory() as directory:
            report = apply_change(
                client, change, approved_sha256=change["sha256"],
                approved_by="human@example.test", audit_log=Path(directory) / "audit.jsonl",
            )
        self.assertEqual("failed", report["status"])
        self.assertEqual([], client.created)


if __name__ == "__main__":
    unittest.main()
