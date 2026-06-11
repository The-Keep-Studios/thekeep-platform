# EspoCRM Assistant

Constrained EspoCRM access for issue
[#28](https://github.com/The-Keep-Studios/thekeep-platform/issues/28).
The MCP server can read records and prepare signed change sets; it cannot apply
or delete anything. See the
[evaluation](../../docs/espocrm-mcp-evaluation.md) for the security boundary.

```bash
python -m venv .venv
. .venv/bin/activate
pip install -e .
export ESPOCRM_URL=https://crm.example.com
export ESPOCRM_READ_API_KEY=...
thekeep-espocrm-mcp
```

Apply a reviewed change set outside the assistant:

```bash
thekeep-espocrm-apply change.json \
  --approve-sha256 <sha256> \
  --approved-by <human-identity>
```

Use separate read-only and write-capable Espo API users. The executor reads
`ESPOCRM_WRITE_API_KEY`; optional HMAC secrets use the same `READ_`/`WRITE_`
prefix. Writes require source attribution; Opportunity writes also require
reciprocal signal evidence or an explicit human override. The executor rejects
stale updates, adds an Espo Note, and appends a mode-`0600` local audit record.

Run the dependency-free tests with:

```bash
PYTHONPATH=src python -m unittest discover -s tests -v
```
