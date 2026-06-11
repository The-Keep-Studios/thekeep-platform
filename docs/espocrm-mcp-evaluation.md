# EspoCRM MCP Evaluation

Reviewed 2026-06-11. Decision: build a narrow internal adapter; do not expose
an existing server directly.

The EspoCRM instance is private and directly controlled. That lowers external
exposure and makes internal-use licenses relevant, but does not remove the need
for least privilege, approval gates, or durable audit records.

## Candidate Comparison

| Candidate | License / activity | Transport and auth | Safety result |
| --- | --- | --- | --- |
| [`zaphod-black/EspoMCP`](https://github.com/zaphod-black/EspoMCP/tree/66d7b46290d02c2b3d9d61fcecda053ea07511c7) | MIT declared in package; no license file; last code 2025-07 | stdio; Espo API key/HMAC | Fixed 47-tool surface includes generic delete/unlink and role/team mutation. Reject direct use. |
| [`highdeserthacker/espocrm-mcp-server`](https://github.com/highdeserthacker/espocrm-mcp-server/tree/b10b335b960e5bac8014111c5610be979bc5e6dd) | BSL 1.1 internal single-instance grant; two commits | SSE behind unauthenticated streamable-HTTP proxy; Espo API key | Entity allowlist and metadata are useful, but every entity gets delete and tool arguments are logged. Reference only. |
| [`przyszloscjestdzisiaj/espocrm-mcp`](https://github.com/przyszloscjestdzisiaj/espocrm-mcp/tree/2971cc350703364478f9ed7530ae48163a2b1bb6) | MIT declared; no license file; one commit | stdio or streamable HTTP; Espo API key | Small, but generic create/update/delete/unlink and no caller auth or tests. Reject. |
| [`megemini/EspoCRM-MCP-Auth0`](https://github.com/megemini/EspoCRM-MCP-Auth0/tree/058343de85ee1ccf798e2f36be98ea45c32f36c8) | Apache-2.0; tests; last code 2026-04 | streamable HTTP; Auth0 scopes; optional FGA; Espo API key/HMAC | Best authorization reference. Still registers generic delete/unlink and all write tools, with no approval or dry-run. |
| [`ground-creative/easy-mcp-espocrm-python`](https://github.com/ground-creative/easy-mcp-espocrm-python/tree/ba17258a9eca8cd3078a7f290d2d2396366bfdb5) | No license; last code 2026-01 | easy-mcp HTTP; Espo URL/key supplied per request | Broad delete tools, credentials in request headers, shared mutable state, incomplete entity coverage. Reject. |
| [`xavfo/espocrm-mcp-server`](https://github.com/xavfo/espocrm-mcp-server) | Identical fork of HighDesertHacker | Same | No independent value. |
| [`kubekub/espocrm-mcp`](https://github.com/kubekub/espocrm-mcp) | Identical fork of zaphod-black | Same | No independent value. |
| [`JuntoAI/espocrm-mcp-server`](https://github.com/JuntoAI/espocrm-mcp-server/tree/1d8e135c12b537318d74ba1865ba546b37317890) | MIT declared; no license file; active 2026-06; unit/property tests | stdio; Espo API key/HMAC | Best Espo behavior reference. Still exposes delete/unlink, user-role mutation, direct writes, and API-key override arguments. |
| [`critter-rafael/EspoMCP`](https://github.com/critter-rafael/EspoMCP) | zaphod fork; Docker-only changes | Same as zaphod | No relevant safety improvement. |
| [`antl3x/EspoMCP`](https://github.com/antl3x/EspoMCP) | Identical fork of zaphod-black | Same | No independent value. |

None supports dry-run change sets, human approval, durable before/after audit,
or a no-delete guarantee. MCP tool annotations are hints, not enforcement, so
marking a tool destructive is insufficient.

## Top References

1. **JuntoAI**: reuse test cases and Espo field/date/search handling. Unsafe
   tools include `delete_entity`, `unlink_entities`, `assign_role_to_user`,
   `remove_user_from_team`, generic create/update, and direct lead conversion.
2. **Auth0/FGA**: reuse OAuth scope and entity-authorization patterns if remote
   multi-user MCP access becomes necessary. Unsafe tools include
   `delete_entity`, `unlink_entities`, generic create/update, team mutation,
   direct opportunity creation, and direct lead conversion.

HighDesertHacker is a useful metadata-discovery example. Its BSL grant appears
compatible with the current private single-instance use, but its operation
surface and unauthenticated proxy still make it unsuitable as the boundary.
Legal review is required before relying on that interpretation.

## Recommendation

Build a small service in this repository using the official Espo REST API and
standard MCP SDK. Do not fork a 40-plus-tool server merely to remove most of
its behavior.

Use a dedicated Espo API user with HMAC authentication when practical and a
Role that grants:

- read: Lead, Opportunity, Account, Contact, Task, Email, Note, Metadata;
- create/edit: Lead, Opportunity, Account, Contact, Task, Note;
- delete: none;
- administration, users, teams, roles, webhooks: none.

Espo officially recommends separate API users with permissions defined by
Roles and exposes instance-specific OpenAPI metadata:
[API](https://docs.espocrm.com/development/api/) and
[roles](https://docs.espocrm.com/administration/roles-management/).

Start with stdio for local evaluation. If remote MCP is needed, place
streamable HTTP behind the platform identity/gateway; never expose a bearerless
MCP endpoint.

## Tool Contract

Assistant-visible tools:

| Tool | Behavior |
| --- | --- |
| `crm_search` | Read allowlisted entities with bounded fields, filters, and result count. |
| `crm_get` | Read one allowlisted record by ID. |
| `crm_metadata` | Return allowlisted fields/enums only. |
| `crm_duplicate_candidates` | Search normalized company, role, URL, recruiter, and email evidence. |
| `crm_prepare_change` | Validate a create/update/link/note/task request and return a non-mutating change set. |
| `crm_export_csv` | Export a prepared change set for manual import. |

Do not expose generic entity names, delete, unlink, role/team changes, email
sending, application submission, or an assistant-callable apply tool.

The approval executor, outside the assistant MCP surface, should:

1. require a human-approved change-set hash;
2. re-read records and reject stale preconditions;
3. enforce entity/field allowlists and no-delete policy;
4. require reciprocal signal or explicit override for Opportunity creation;
5. append source attribution and an assistant-origin audit note;
6. record actor, approver, request ID, source, before/after values, time, and
   resulting Espo IDs;
7. return an applied-changes report.

This contract directly supports [#28](https://github.com/The-Keep-Studios/thekeep-platform/issues/28)
without granting the model unrestricted EspoCRM access.
