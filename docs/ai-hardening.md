# AI Hardening Gate

Apply this after the #15 gateway has runnable identity, policy, retrieval,
provider, tool proposal, approval, and audit paths. Documentation is not
evidence; the controls must be tested against the implementation.

## Invariants

1. Retrieved content cannot grant permission or select tools.
2. Models/services cannot approve their own proposals.
3. Request text cannot expand source, field, provider, target, or tool scope.
4. Confidential context cannot fall back to an unapproved provider.
5. Every write is attributable to actor, service, workflow, approval, and
   target result.
6. Altered, expired, reused, or partially failed proposals do not execute.
7. Audit/log/error paths do not copy confidential payloads.
8. Failure reduces capability; it never bypasses policy.
9. Every provider, connector, and tool has a tested kill switch.

## Tool Admission

Every enabled tool declares:

- stable domain-specific ID, owner, and purpose;
- action level;
- dedicated credential;
- source/target entity and field allowlists;
- strict input/output schemas;
- batch/rate/time/retry limits;
- approval and idempotency behavior;
- audit fields, rollback, tests, and kill switch.

Reject generic CRUD, shell, SQL, browser, arbitrary HTTP, admin credentials, or
tools whose destructive actions cannot be removed.

## Approval

- **No per-action approval:** public reads, health/schema checks, explicitly
  scoped internal reads.
- **Human approval:** internal writes, cross-system links, hosted-provider use
  for confidential data, write-capable prompt/policy/tool changes, limit
  increases.
- **Exact-payload approval:** external communication, public publication,
  recipients/attachments, Lead-to-Opportunity promotion, destructive actions,
  and production operations.

Approval binds digest, actor, target, fields/values, policy/tool version, expiry,
and execution count.

Stop for maintainer review on unknown classification, source/target conflict,
low-confidence duplicate, out-of-contract action, provider boundary crossing,
missing audit/policy control, injection indicator, or partial/unknown result.

## Audit Assertions

Required fields:

- event/correlation/time;
- actor and service identity;
- deployment/workflow and policy/prompt/provider/model/tool versions;
- source references/classifications;
- target entity/record and changed field names;
- policy decision;
- approval actor/time/ID;
- execution result/error, latency, tokens, and cost where applicable.

Tests must prove:

- each write has proposal and required approval;
- proposal/execution digests match;
- denials have no mutation;
- audit identities are never blank;
- normal gateway identities cannot alter audit records;
- credentials, headers, hidden reasoning, full emails/transcripts,
  attachments, and unrestricted prompts are absent;
- confidential reads and writes fail closed when audit storage is unavailable.

## Retention Proposal

| Data | Default |
| --- | --- |
| Raw prompts/provider responses/source bodies | Not persisted |
| Validated output | Request lifetime unless workflow declares otherwise |
| Tool proposals | Expiry plus incident-review window |
| Approval records | Audit retention |
| Redacted audit events | 90 days, pending review |
| Content-free aggregate metrics | 13 months |

Exceptions declare purpose, class, owner, access, storage, duration, deletion,
backup, and provider implications. Scheduled deletion covers caches, proposals,
outputs, vectors, and backups' documented recovery window.

## Required Negative Tests

### Identity And Retrieval

- missing auth -> `401`, no provider/connector call;
- insufficient role -> `403` and denial event;
- caller-supplied roles ignored;
- service cannot call another service's workflow;
- unknown/wildcard source/tool denied;
- cross-user cache returns nothing;
- disallowed fields removed/denied;
- malicious source instructions remain quoted data;
- unexpected connector schema fails before model invocation.

### Provider

- disabled hosted provider does not receive fallback traffic;
- confidential workflow without approved provider is denied;
- timeout/retry is bounded;
- malformed structured output creates no proposal;
- payloads are redacted from provider errors;
- token/cost limits stop the request.

### Tool And Approval

- unregistered tool and unknown fields rejected;
- out-of-scope target denied;
- altered/expired/reused/self-approved proposal denied;
- idempotency retry creates no duplicate;
- partial/unknown result stops without blind retry;
- missing audit sink denies write.

### External/Destructive

- email is draft-only without exact approval;
- changed recipient/attachment invalidates approval;
- delete/generic mutation tools are absent;
- ops assistant cannot execute production commands;
- GitHub merge/close/release tools are absent.

Use synthetic direct/indirect prompt-injection fixtures, including instructions
inside email, HTML, issues, transcripts, CRM text, encoded content, split
records, and tool output. The invariant is that content can affect an answer,
never identity, policy, provider, retrieval, approval, or tool scope.

## Operational Gate

- separate API/executor/connector/audit identities;
- default-deny network access;
- internal-only gateway/executor;
- pinned/scanned dependencies and images;
- resource, queue, token, timeout, retry, concurrency, and budget limits;
- readiness based on required policy/audit/provider dependencies;
- alerts for denials, injection indicators, audit failure, queue/latency/cost;
- tested provider/tool kill switches;
- backup/restore for policy, prompts, approvals, and audit;
- tabletop credential-compromise/unintended-write incident.

## Release Levels

- **Internal read-only:** identity/retrieval isolation, redaction, limits, and
  kill switches pass.
- **Internal write:** tool review, dry run, approval, idempotency, audit
  fail-closed, and compensating action pass.
- **External/client:** tenant isolation, consent/retention/provider terms,
  exact-payload approval, incident ownership, limited rollout, and human risk
  acceptance pass.

## Decisions Needed

- 90-day audit retention;
- whether any low-risk writes may use standing workflow approval;
- hosted providers allowed by classification;
- approvers for external/production actions;
- tenant-isolation requirements;
- availability/recovery objectives;
- gateway-local versus shared approval service.
