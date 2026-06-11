from __future__ import annotations

from typing import Any

from .client import EspoClient
from .policy import READ_FIELDS, PolicyError, export_csv, prepare_change, validate_filters


def _bounded(value: Any) -> Any:
    if isinstance(value, str):
        return value[:20_000]
    if isinstance(value, list):
        return value[:100]
    return value


class EspoAssistant:
    def __init__(self, client: EspoClient) -> None:
        self.client = client

    def search(
        self,
        entity: str,
        *,
        filters: list[dict[str, Any]] | None = None,
        text: str | None = None,
        fields: list[str] | None = None,
        limit: int = 20,
    ) -> Any:
        filters = filters or []
        validate_filters(entity, filters)
        selected = fields or sorted(READ_FIELDS[entity])
        if not 1 <= limit <= 50 or set(selected) - READ_FIELDS[entity]:
            raise PolicyError("invalid field selection or result limit")
        params: dict[str, Any] = {
            "where": filters,
            "maxSize": limit,
            "select": selected,
        }
        if text:
            params["textFilter"] = text[:200]
        response = self.client.search(entity, params)
        return {
            "total": response.get("total"),
            "list": [
                {key: _bounded(value) for key, value in record.items() if key in selected}
                for record in response.get("list", [])
            ],
        }

    def get(self, entity: str, record_id: str, fields: list[str] | None = None) -> dict[str, Any]:
        from .policy import validate_record_id

        validate_record_id(record_id)
        selected = set(fields or READ_FIELDS.get(entity, set()))
        if entity not in READ_FIELDS or selected - READ_FIELDS[entity]:
            raise PolicyError("invalid entity or field selection")
        record = self.client.get(entity, record_id)
        return {key: _bounded(value) for key, value in record.items() if key in selected}

    def metadata(self, entity: str) -> dict[str, Any]:
        if entity not in READ_FIELDS:
            raise PolicyError("entity is not readable")
        fields = self.client.metadata().get("entityDefs", {}).get(entity, {}).get("fields", {})
        return {
            name: {
                key: value for key, value in definition.items()
                if key in {"type", "required", "options", "default"}
            }
            for name, definition in fields.items()
            if name in READ_FIELDS[entity]
        }

    def duplicate_candidates(self, fields: dict[str, Any]) -> list[dict[str, Any]]:
        searches = []
        for entity, attribute, match, value in (
            ("Lead", "emailAddress", "equals", fields.get("emailAddress")),
            ("Contact", "emailAddress", "equals", fields.get("emailAddress")),
            ("Lead", "accountName", "contains", fields.get("accountName")),
            ("Account", "name", "contains", fields.get("accountName")),
            ("Lead", "website", "equals", fields.get("website") or fields.get("sourceUrl")),
            ("Account", "website", "equals", fields.get("website")),
            ("Lead", "name", "contains", fields.get("name")),
            ("Opportunity", "name", "contains", fields.get("name")),
        ):
            if value:
                searches.append((entity, attribute, match, value))

        found: dict[tuple[str, str], dict[str, Any]] = {}
        for entity, attribute, match, value in searches[:8]:
            response = self.search(
                entity,
                filters=[{"type": match, "attribute": attribute, "value": str(value)[:200]}],
                fields=["id", "name", "modifiedAt"],
                limit=10,
            )
            for record in response.get("list", []):
                if record.get("id"):
                    found[(entity, record["id"])] = {
                        "entity": entity,
                        "id": record["id"],
                        "name": record.get("name"),
                        "matchedOn": attribute,
                    }
        return list(found.values())

    def prepare_change(self, **request: Any) -> dict[str, Any]:
        candidates = (
            self.duplicate_candidates(request["fields"])
            if request["operation"] == "create" and request["entity"] in {"Lead", "Opportunity"}
            else []
        )
        return prepare_change(**request, duplicate_candidates=candidates)

    @staticmethod
    def export_csv(changes: list[dict[str, Any]]) -> str:
        return export_csv(changes)
