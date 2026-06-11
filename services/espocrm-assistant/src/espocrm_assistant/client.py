from __future__ import annotations

import base64
import hashlib
import hmac
import json
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

Transport = Callable[
    [str, str, Mapping[str, str], bytes | None, float],
    tuple[int, bytes],
]


class EspoError(RuntimeError):
    pass


def _urllib_transport(
    method: str,
    url: str,
    headers: Mapping[str, str],
    body: bytes | None,
    timeout: float,
) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, headers=dict(headers), method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


class EspoClient:
    def __init__(
        self,
        base_url: str,
        api_key: str,
        *,
        secret_key: str | None = None,
        auth_method: str = "apikey",
        allow_http: bool = False,
        timeout: float = 30,
        transport: Transport | None = None,
    ) -> None:
        parsed = urllib.parse.urlparse(base_url)
        if parsed.scheme != "https" and not allow_http:
            raise ValueError("ESPOCRM_URL must use HTTPS")
        if not parsed.netloc or not api_key:
            raise ValueError("EspoCRM URL and API key are required")
        if auth_method not in {"apikey", "hmac"}:
            raise ValueError("auth_method must be apikey or hmac")
        if auth_method == "hmac" and not secret_key:
            raise ValueError("HMAC authentication requires a secret key")

        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.secret_key = secret_key
        self.auth_method = auth_method
        self.timeout = timeout
        self.transport = transport or _urllib_transport

    def _auth_headers(self, method: str, action: str) -> dict[str, str]:
        if self.auth_method == "apikey":
            return {"X-Api-Key": self.api_key}

        message = f"{method} /{action}".encode()
        digest = hmac.new(self.secret_key.encode(), message, hashlib.sha256).hexdigest()
        token = base64.b64encode(f"{self.api_key}:{digest}".encode()).decode()
        return {"X-Hmac-Authorization": token}

    def request(
        self,
        method: str,
        action: str,
        *,
        query: Mapping[str, Any] | None = None,
        data: Mapping[str, Any] | None = None,
    ) -> Any:
        method = method.upper()
        clean_action = action.strip("/")
        url = f"{self.base_url}/api/v1/{urllib.parse.quote(clean_action, safe='/')}"
        if query:
            url += "?" + urllib.parse.urlencode(query)

        headers = {"Accept": "application/json", **self._auth_headers(method, clean_action)}
        body = None
        if data is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(data, separators=(",", ":")).encode()

        status, payload = self.transport(method, url, headers, body, self.timeout)
        if status < 200 or status >= 300:
            detail = payload.decode(errors="replace")[:500]
            raise EspoError(f"EspoCRM returned HTTP {status}: {detail}")
        if not payload:
            return None
        try:
            return json.loads(payload)
        except json.JSONDecodeError as error:
            raise EspoError("EspoCRM returned invalid JSON") from error

    def search(self, entity: str, search_params: Mapping[str, Any]) -> Any:
        params = json.dumps(search_params, sort_keys=True, separators=(",", ":"))
        return self.request("GET", entity, query={"searchParams": params})

    def get(self, entity: str, record_id: str) -> Any:
        return self.request("GET", f"{entity}/{record_id}")

    def metadata(self) -> Any:
        return self.request("GET", "Metadata")

    def create(self, entity: str, fields: Mapping[str, Any]) -> Any:
        return self.request("POST", entity, data=fields)

    def update(self, entity: str, record_id: str, fields: Mapping[str, Any]) -> Any:
        return self.request("PUT", f"{entity}/{record_id}", data=fields)
