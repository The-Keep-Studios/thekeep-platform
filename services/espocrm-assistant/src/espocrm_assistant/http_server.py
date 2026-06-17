from __future__ import annotations

import json
import os
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from .client import EspoClient, EspoError
from .executor import apply_change
from .policy import PolicyError
from .service import EspoAssistant

_service: EspoAssistant | None = None
_write_client: EspoClient | None = None


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


def write_client() -> EspoClient:
    global _write_client
    if _write_client is None:
        _write_client = EspoClient(
            os.environ["ESPOCRM_URL"],
            os.environ["ESPOCRM_WRITE_API_KEY"],
            secret_key=os.getenv("ESPOCRM_WRITE_SECRET_KEY"),
            auth_method=os.getenv("ESPOCRM_WRITE_AUTH_METHOD", "apikey"),
            allow_http=os.getenv("ESPOCRM_ALLOW_HTTP") == "1",
        )
    return _write_client


def audit_log_path() -> Path:
    return Path(
        os.getenv(
            "ESPOCRM_ASSISTANT_AUDIT_LOG",
            "~/.local/state/thekeep/espocrm-assistant-audit.jsonl",
        )
    ).expanduser()


def dispatch(assistant: EspoAssistant, path: str, payload: dict[str, Any]) -> Any:
    if path == "/crm/search":
        return assistant.search(**payload)
    if path == "/crm/get":
        return assistant.get(**payload)
    if path == "/crm/metadata":
        return assistant.metadata(**payload)
    if path == "/crm/duplicate-candidates":
        return assistant.duplicate_candidates(**payload)
    if path == "/crm/prepare-change":
        return assistant.prepare_change(**payload)
    if path == "/crm/prepare-lead-conversion":
        return assistant.prepare_lead_conversion(**payload)
    if path == "/crm/export-csv":
        return {"csv": assistant.export_csv(payload.get("changes", []))}
    raise KeyError(path)


def dispatch_approval(client: EspoClient, payload: dict[str, Any], audit_log: Path) -> dict[str, Any]:
    change = payload.get("change")
    if not isinstance(change, dict):
        raise ValueError("change is required")
    return apply_change(
        client,
        change,
        approved_sha256=str(payload.get("approved_sha256", "")),
        approved_by=str(payload.get("approved_by", "")),
        audit_log=audit_log,
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "TheKeepEspoAssistant/0.1"

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send(self, status: int, value: Any) -> None:
        body = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self, env_name: str) -> bool:
        token = os.getenv(env_name, "")
        if not token:
            return False
        return hmac.compare_digest(
            self.headers.get("Authorization", ""),
            f"Bearer {token}",
        )

    def _read_payload(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1_000_000:
            raise OverflowError("request too large")
        payload = json.loads(self.rfile.read(length) or b"{}")
        if not isinstance(payload, dict):
            raise ValueError("request body must be a JSON object")
        return payload

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self._send(200, {"status": "ok"})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path == "/approval/apply-change":
            if not self._authorized("ESPOCRM_ASSISTANT_APPLY_TOKEN"):
                self._send(401, {"error": "unauthorized"})
                return
            try:
                report = dispatch_approval(write_client(), self._read_payload(), audit_log_path())
                self._send(200 if report.get("status") == "applied" else 409, report)
            except OverflowError as error:
                self._send(413, {"error": str(error)})
            except (EspoError, PolicyError, ValueError, TypeError, json.JSONDecodeError) as error:
                self._send(400, {"error": str(error)})
            return

        if not self._authorized("ESPOCRM_ASSISTANT_TOKEN"):
            self._send(401, {"error": "unauthorized"})
            return
        try:
            payload = self._read_payload()
            self._send(200, dispatch(service(), self.path, payload))
        except OverflowError as error:
            self._send(413, {"error": str(error)})
        except KeyError:
            self._send(404, {"error": "not found"})
        except (EspoError, PolicyError, ValueError, TypeError, json.JSONDecodeError) as error:
            self._send(400, {"error": str(error)})


def main() -> None:
    host = os.getenv("ESPOCRM_ASSISTANT_HOST", "0.0.0.0")
    port = int(os.getenv("ESPOCRM_ASSISTANT_PORT", "8080"))
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
