# EspoCRM Assistant

Constrained EspoCRM access for issue
[#28](https://github.com/The-Keep-Studios/thekeep-platform/issues/28).
The assistant-visible MCP server can read records and prepare signed change
sets; it cannot apply or delete anything. See the
[evaluation](../../docs/espocrm-mcp-evaluation.md) for the build-vs-wrap
decision and security boundary.

```bash
python -m venv .venv
. .venv/bin/activate
pip install -e .
export ESPOCRM_URL=https://crm.example.com
export ESPOCRM_READ_API_KEY=...
thekeep-espocrm-mcp
```

Run streamable HTTP MCP for an internal gateway:

```bash
export ESPOCRM_MCP_HOST=0.0.0.0
export ESPOCRM_MCP_PORT=8080
export ESPOCRM_MCP_PATH=/mcp
thekeep-espocrm-mcp-http
```

Do not expose the streamable HTTP endpoint directly to the internet. Production
should keep it internal and place OAuth/OIDC and per-user authorization in front
of it through the platform MCP gateway tracked by
[#54](https://github.com/The-Keep-Studios/thekeep-platform/issues/54).

Apply a reviewed change set outside the assistant, either locally:

```bash
thekeep-espocrm-apply change.json \
  --approve-sha256 <sha256> \
  --approved-by <human-identity>
```

or through the deployed approval endpoint:

```bash
curl -fsS http://espocrm-assistant.espocrm.svc.cluster.local:8090/approval/apply-change \
  -H "Authorization: Bearer ${ESPOCRM_ASSISTANT_APPLY_TOKEN}" \
  -H "Content-Type: application/json" \
  --data @approved-change.json
```

`approved-change.json` must contain `change`, `approved_sha256`, and
`approved_by`. The approval endpoint uses separate write credentials and is not
registered as an MCP tool.

Use separate read-only and write-capable Espo API users. The executor reads
`ESPOCRM_WRITE_API_KEY`; optional HMAC secrets use the same `READ_`/`WRITE_`
prefix. The deployed approval endpoint additionally requires
`ESPOCRM_ASSISTANT_APPLY_TOKEN` and writes audit records to
`ESPOCRM_ASSISTANT_AUDIT_LOG`. Writes require source attribution; Opportunity
writes also require reciprocal signal evidence or an explicit human override.
The executor rejects stale updates, adds an Espo Note, and appends a mode-`0600`
audit record.

Run the dependency-free tests with:

```bash
PYTHONPATH=src python -m unittest discover -s tests -v
```
