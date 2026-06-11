from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .client import EspoClient
from .service import EspoAssistant

mcp = FastMCP("thekeep-espocrm")
_service: EspoAssistant | None = None


def service() -> EspoAssistant:
    global _service
    if _service is None:
        _service = EspoAssistant(EspoClient(
            os.environ["ESPOCRM_URL"],
            os.environ["ESPOCRM_READ_API_KEY"],
            secret_key=os.getenv("ESPOCRM_READ_SECRET_KEY"),
            auth_method=os.getenv("ESPOCRM_READ_AUTH_METHOD", "apikey"),
            allow_http=os.getenv("ESPOCRM_ALLOW_HTTP") == "1",
        ))
    return _service


@mcp.tool()
def crm_search(
    entity: str,
    filters: list[dict[str, Any]] | None = None,
    text: str | None = None,
    fields: list[str] | None = None,
    limit: int = 20,
) -> Any:
    """Search allowlisted CRM records without mutation."""
    return service().search(entity, filters=filters, text=text, fields=fields, limit=limit)


@mcp.tool()
def crm_get(entity: str, record_id: str, fields: list[str] | None = None) -> Any:
    """Read one allowlisted CRM record."""
    return service().get(entity, record_id, fields)


@mcp.tool()
def crm_metadata(entity: str) -> Any:
    """Read allowlisted field metadata for one entity."""
    return service().metadata(entity)


@mcp.tool()
def crm_duplicate_candidates(fields: dict[str, Any]) -> Any:
    """Find possible duplicates from identifying fields."""
    return service().duplicate_candidates(fields)


@mcp.tool()
def crm_prepare_change(request: dict[str, Any]) -> Any:
    """Prepare and hash a non-mutating create or update change set."""
    return service().prepare_change(**request)


@mcp.tool()
def crm_export_csv(changes: list[dict[str, Any]]) -> str:
    """Export validated change sets as CSV for manual import."""
    return service().export_csv(changes)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
