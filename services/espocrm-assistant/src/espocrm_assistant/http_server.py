from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .client import EspoClient, EspoError
from .policy import PolicyError
from .service import EspoAssistant

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
    if path == "/crm/export-csv":
        return {"csv": assistant.export_csv(payload.get("changes", []))}
    raise KeyError(path)


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

    def _authorized(self) -> bool:
        token = os.getenv("ESPOCRM_ASSISTANT_TOKEN", "")
        if not token:
            return False
        return self.headers.get("Authorization") == f"Bearer {token}"

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self._send(200, {"status": "ok"})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        if not self._authorized():
            self._send(401, {"error": "unauthorized"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 1_000_000:
                self._send(413, {"error": "request too large"})
                return
            payload = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(payload, dict):
                raise ValueError("request body must be a JSON object")
            self._send(200, dispatch(service(), self.path, payload))
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
