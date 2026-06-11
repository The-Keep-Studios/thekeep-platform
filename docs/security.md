# Platform Security Baseline

This is the minimum target before integrations or AI tools receive meaningful
write access. It does not claim every control is implemented.

## Boundaries

```text
Internet -> Cloudflare/Traefik -> Authentik -> application authorization
                                             -> connector/tool policy
```

- Cloudflare/Traefik control exposure and routing.
- Authentik establishes identity.
- Applications authorize records and operations.
- Connectors constrain cross-system access.
- AI models propose; deterministic policy authorizes.

Passing one boundary does not bypass the next.

## Deployment Classes

- **Public:** intentional non-confidential content only.
- **Demo:** separate credentials, synthetic data, resettable state, no internal
  network access or external communication by default.
- **Internal:** authenticated confidential operating data.
- **Production administration:** explicit operator intent, validation, and
  short-lived elevation where practical.

## Roles

| Role | Scope |
| --- | --- |
| Public visitor | Public content |
| Demo user | Synthetic, non-destructive demo workflows |
| Internal member | Authorized internal records |
| Data steward | Approved changes within one system |
| Operator | Bounded deployment, backup, and recovery operations |
| Maintainer | Architecture and production risk approval |
| Service identity | Fixed API/resource allowlist for one integration |
| AI assistant | No inherent privilege; uses constrained service identities |

Forward-auth membership does not imply application administration. AI
assistants never inherit all permissions of the interacting human.

## Action Levels

| Level | Default |
| --- | --- |
| Public read | Allowed |
| Internal read | Authorized role and purpose required |
| Draft/dry run | Preferred for writes |
| Internal write | Exact approval or explicitly reviewed bounded workflow |
| External write | Human approval for exact payload |
| Destructive | Human approval plus recovery plan |
| Privileged | Maintainer/operator approval and production validation |

Unknown identity, scope, classification, or approval means deny.

## Approval

A write workflow:

1. gathers authorized source records;
2. produces an exact dry run;
3. applies policy and duplicate checks;
4. obtains human approval;
5. binds approval to proposal digest, target, values, actor, policy version, and
   expiry;
6. executes idempotently;
7. returns per-action results.

Reject altered, expired, reused, or self-approved proposals.

## Audit Event

Sensitive reads and all writes record:

- event/correlation ID and time;
- human actor and service identity;
- deployment, workflow, policy, prompt, provider, model, and tool versions;
- source references and classifications;
- target system/entity/record;
- operation and changed field names;
- policy decision and reason;
- approval actor/time/ID when required;
- execution status, target result ID, latency, and cost where applicable.

Store redacted summaries, not credentials, authentication headers, hidden model
reasoning, full emails/transcripts, attachments, or unrestricted prompts.
Confidential reads and writes fail closed if required audit storage is
unavailable.

## Secrets

Current state: local ignored production vars are validated by Ansible and
written to Kubernetes Secrets.

Required baseline:

- one credential per service identity and environment;
- least-privilege API and Kubernetes RBAC;
- short-lived credentials where supported;
- encryption of Kubernetes Secret data at rest;
- no secret values in Git, shell history, process arguments, logs, screenshots,
  AI prompts, or audit events;
- documented owner, purpose, scope, rotation, and revocation;
- migration to SOPS or External Secrets through a separate reviewed change.

Follow Kubernetes' official
[Secrets good practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices/).

## Data Handling

Use four classes: public, internal, confidential, restricted.

- Apply the most restrictive class when combining records.
- Retrieve only required records and fields.
- Prefer source references over copied bodies.
- Keep public/demo indexes separate from confidential data.
- Do not send confidential content to a hosted model without approved provider
  and retention terms.
- Define deletion before ingesting transcripts or mailboxes.
- Never ingest credentials or specially sensitive restricted records into model
  context.

## AI Tool Rules

Retrieved text is untrusted data and cannot grant authority.

- Enforce retrieval and tool policy outside the model.
- Expose narrow domain actions, not generic shell/HTTP/SQL/browser/CRUD.
- Validate model output against strict schemas.
- Reject unknown fields and enum values.
- Require field, record, recipient, batch, rate, time, and cost limits.
- Prevent the model/service identity from approving its own proposal.
- Keep confidential context from falling back to an unapproved provider.
- Pin and review dependencies, containers, models, and prompt versions.
- Fail closed or read-only; never broaden access during failure.

Use the
[OWASP GenAI Security Project](https://genai.owasp.org/llm-top-10/)
and [NIST AI RMF Playbook](https://www.nist.gov/itl/ai-risk-management-framework/nist-ai-rmf-playbook)
as external threat-model references instead of duplicating them here.

## Verification Gate

Before enabling a connector/tool:

- positive and negative identity/permission tests pass;
- source, entity, field, provider, and tool allowlists are enforced;
- public/confidential isolation is tested;
- dry-run, digest, expiry, idempotency, and partial-failure behavior pass;
- injection fixtures cannot change policy or invoke tools;
- audit completeness/redaction is verified;
- rate, context, cost, timeout, retry, disable, and rollback controls exist;
- external and destructive actions are unavailable without exact approval.

## Incident Response

1. Disable the affected connector/tool/identity.
2. Stop queued actions and retries.
3. Preserve redacted evidence.
4. Rotate/revoke credentials.
5. Determine affected records, recipients, and time range.
6. Restore or compensate without deleting evidence.
7. Record root cause and prevention.
8. Handle disclosure through `SECURITY.md`.

## Follow-Up Work

Existing tracks:

- #15 AI gateway and policy enforcement;
- #18 connector ownership;
- #23 implementation hardening;
- #28 constrained EspoCRM interface;
- #29 EspoCRM MCP evaluation.

After review, create focused issues for Authentik role reconciliation/MFA,
Secret encryption/RBAC verification, structured audit storage, approval tokens,
and automated negative security tests.
