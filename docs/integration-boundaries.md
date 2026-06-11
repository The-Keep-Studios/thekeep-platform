# Integration Boundaries

Integrations reduce duplicate entry without erasing ownership or spreading
confidential data.

## Rules

1. Every record type has one canonical system.
2. Read access does not imply write access.
3. Connectors use record and field allowlists.
4. Copies retain source system, ID, URL, and timestamp.
5. Writes start as dry-run proposals.
6. Deletion, external communication, and public publication require direct
   human approval.
7. Ambiguous identity, scope, classification, or approval fails closed.
8. Bidirectional sync is not the default.

## Ownership

| Record | Canonical system |
| --- | --- |
| Public roadmap, code, issues, reviews | GitHub |
| Private execution, workload, client-specific tasks | Leantime |
| Active job, sales, client, consulting, publishing opportunities | EspoCRM |
| General relationship and organization memory | Baserow |
| Messages and threads | Gmail/Espo Email when deliberately imported |
| Meeting transcript and derived record | Future meeting-memory store |
| Identity and access policy | Authentik plus application authorization |

A link or summary elsewhere does not transfer ownership.

## Action Policy

| System | Allowed reads | Approval-gated writes | Human-only/prohibited |
| --- | --- | --- | --- |
| GitHub | Issues, PRs, commits, docs | Draft issue/PR, focused branch, progress comment | Merge, close, release, settings, confidential evidence |
| Leantime | Scoped projects, tasks, comments | Create/update task or progress note | Delete/bulk reschedule; publish private task content |
| EspoCRM | Leads, Opportunities, Accounts, Contacts, Tasks, relevant Emails, metadata | Dry-run-approved Lead/Opportunity/Task changes | Delete, auto-apply, unsolicited contact, cold item promoted without reciprocal signal |
| Baserow | Approved people, organizations, interactions | Reviewed create/update/link | Bulk merge/delete/import; external exposure |
| Gmail | Narrow search and required message evidence | Draft reply; explicitly approved label | Send, add recipients/attachments, delete/archive/forward, unrestricted ingestion |

For Gmail, prefer a source reference and concise evidence summary over copying a
full body or attachment.

## Automation Levels

- **Read:** retrieve scoped records.
- **Propose:** return a dry run or draft.
- **Approve:** human accepts exact targets and values.
- **Execute:** constrained connector applies the approved proposal.
- **Prohibited:** deletion, publication, sending, merge, or boundary crossing.

Approval is bound to a proposal digest, target, fields, actor, and expiry. It is
not permission for adjacent writes.

## Connector Contract

Before implementation, define:

- actor and dedicated credential;
- source of truth and destination;
- entity/field allowlists and data classification;
- query, batch, rate, timeout, and retry limits;
- stable source ID, duplicate detection, and idempotency;
- dry-run and approval format;
- audit fields and payload redaction;
- partial-failure and rollback behavior;
- retention/deletion behavior;
- operator metrics and kill switch.

Do not use a shared administrator credential when a narrower identity is
possible.

## Audit Minimum

Every assistant-originated write records:

- actor, service identity, workflow, and correlation ID;
- source references;
- target system/entity/record;
- proposed changed fields;
- approval actor, time, and ID;
- execution result and stable error code.

Audit records contain redacted summaries, not credentials or full confidential
payloads.

## First Prototype

Start with a read-only public GitHub/Markdown connector:

1. allowlist repositories and paths;
2. preserve source IDs, URLs, authors, versions, and timestamps;
3. emit portable Markdown/JSON records;
4. support incremental reindex and deletion;
5. perform no writes.

This tests provenance and indexing without private CRM or mailbox data.

Next, after #20 and #29 are reviewed, add EspoCRM read/search and dry-run Lead
preparation. Writes remain disabled until approval and audit controls exist.

## Keep Out Of Public GitHub

- credentials and production exports;
- client and private workload details;
- job applications, compensation, recruiter conversations, and pipeline state;
- private contacts, email bodies, attachments, and relationship notes;
- raw AI prompts/tool logs containing internal records;
- vulnerability details before responsible disclosure.

Use synthetic examples.

## Failure Behavior

- reads are side-effect free and retryable;
- writes use idempotency keys;
- unknown/partial results stop for review rather than retry blindly;
- rejected or expired approvals cannot be reused;
- source/target conflicts create a manual-review item;
- rollback prefers a compensating update that preserves history.
