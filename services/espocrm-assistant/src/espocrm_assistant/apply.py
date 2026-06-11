from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from .client import EspoClient
from .executor import apply_change


def _write_private(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())
    finally:
        os.close(descriptor)
    os.chmod(path, 0o600)


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply one human-approved EspoCRM change set")
    parser.add_argument("change_set", type=Path)
    parser.add_argument("--approve-sha256", required=True)
    parser.add_argument("--approved-by", required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--audit-log",
        type=Path,
        default=Path("~/.local/state/thekeep/espocrm-assistant-audit.jsonl").expanduser(),
    )
    args = parser.parse_args()

    change = json.loads(args.change_set.read_text())
    client = EspoClient(
        os.environ["ESPOCRM_URL"],
        os.environ["ESPOCRM_WRITE_API_KEY"],
        secret_key=os.getenv("ESPOCRM_WRITE_SECRET_KEY"),
        auth_method=os.getenv("ESPOCRM_WRITE_AUTH_METHOD", "apikey"),
        allow_http=os.getenv("ESPOCRM_ALLOW_HTTP") == "1",
    )
    report = apply_change(
        client,
        change,
        approved_sha256=args.approve_sha256,
        approved_by=args.approved_by,
        audit_log=args.audit_log,
    )
    if args.report:
        _write_private(args.report, report)
    print(json.dumps(report, indent=2, sort_keys=True))
    if report["status"] != "applied":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
