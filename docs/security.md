# Platform Security Baseline

This document defines the minimum security model for The Keep Platform before
integrations or AI tools receive meaningful read or write access.

It is a target baseline, not a claim that every control is implemented today.
Sections distinguish current controls from required follow-up work.

## Security Objectives

The platform should:

- authenticate every non-public user and service;
- authorize actions by role, resource, operation, and data classification;
- grant each credential the minimum useful scope;
- preserve an audit trail for sensitive reads and every write;
- require human approval for destructive or externally visible actions;
- keep confidential operating data out of public systems and model-provider
  requests unless explicitly approved;
- fail closed when identity, scope, policy, or approval state is ambiguous;
- remain recoverable when a credential, integration, or AI workflow misbehaves.

## Trust Boundaries

```text
Public internet
    |
Cloudflare edge and tunnel
    |
Traefik ingress
    |
Authentik identity boundary
    |
Application authorization
    |
Application and integration data
```

Each layer has a separate responsibility:

- Cloudflare and Traefik control network exposure and routing.
- Authentik establishes the user identity and group claims.
- Each application controls resource-level authorization.
- Connector and AI policies constrain cross-system access and tool actions.
- Audit records establish who requested, approved, and executed an action.

Passing one boundary does not grant unrestricted access through the next.

## Deployment Classes

### Public

Public services intentionally expose non-confidential content without login.
They must not share databases, credentials, uploads, logs, or search indexes
with confidential systems merely for convenience.

### Demo

Demo deployments use synthetic data and separate credentials. They must:

- contain no production exports or copied contact records;
- use non-production API keys and provider projects;
- disable external communication and destructive integrations by default;
- support reset to a known synthetic state;
- show visible demo labeling;
- avoid network access to confidential internal services.

### Internal

Internal deployments may contain project, CRM, job-search, relationship, email,
and meeting data. They require authenticated access and application-level
authorization even when they are directly controlled and not intended for
external users.

### Production Administration

Production administration includes cluster, GitOps, DNS, identity, secret,
backup, and database operations. It requires explicit operator intent,
short-lived elevation where practical, and validation evidence.

## Identity Model

Authentik is the intended central identity provider.

Preferred patterns:

1. native OIDC for applications that correctly consume identity and group
   claims;
2. Authentik forward-auth as an additional edge gate for applications without a
   suitable native integration;
3. separate non-human service identities for connectors and automation;
4. no shared human administrator accounts.

Current state:

- Authentik and forward-auth components are deployed;
- forward-auth attachment is deliberate rather than global;
- some application/provider setup remains manual;
- application-local accounts and authorization still exist.

Required follow-up:

- automate provider and application reconciliation;
- define group-to-application-role mappings;
- require MFA for maintainers and production operators;
- document recovery codes and break-glass access;
- review stale users, service identities, and credentials on a schedule.

## Roles

Roles are cumulative only where explicitly stated. Applications may use more
specific roles, but they must not silently grant broader rights than these
platform roles.

| Role | Intended access |
| --- | --- |
| Public visitor | Intentionally public content only |
| Demo user | Synthetic demo data and non-destructive demo workflows |
| Internal member | Authorized internal application records |
| Data steward | Approved create/update and data-quality operations within one system |
| Operator | Deployment observation, backup, restore, and bounded runtime operations |
| Maintainer | Repository, architecture, identity, and production change approval |
| Service identity | Fixed API and resource allowlist for one integration |
| AI assistant | No inherent privilege; acts through a constrained service identity and approval policy |

Important constraints:

- AI assistants do not inherit the full permissions of the human interacting
  with them.
- Service identities are not maintainers.
- Forward-auth membership does not imply application administration.
- Operator access does not imply permission to read all business records.
- Break-glass access is temporary, individually attributable, and reviewed
  after use.

## Authorization Model

Every action decision evaluates:

- actor identity and role;
- service identity and credential scope;
- deployment class;
- source and destination systems;
- entity and record;
- requested fields;
- data classification;
- action risk level;
- approval state;
- request limits and current policy version.

Default deny applies when any required input is missing.

### Action Levels

| Level | Examples | Default policy |
| --- | --- | --- |
| Read public | Public docs and public GitHub metadata | Allowed |
| Read internal | Scoped CRM, project, email, or meeting search | Authorized role and purpose required |
| Draft | Dry-run CRM patch, email draft, draft issue/PR | Allowed within scoped workflow |
| Internal write | Create/update task, Lead, note, or relationship record | Human approval or explicitly approved bounded workflow |
| External write | Send email, publish content, contact a person | Direct human approval for exact payload |
| Destructive | Delete, merge records, revoke access, prune state | Direct human approval plus rollback/recovery plan |
| Privileged | Deploy, change auth, rotate shared credentials, restore database | Maintainer/operator approval and production validation |

Approval is bound to the exact action, target, fields, and expiry. It is not a
general authorization for adjacent actions.

## Approval Workflow

A write-capable workflow follows:

1. gather authorized source records;
2. generate a dry-run proposal;
3. apply policy and duplicate checks;
4. display target records and exact field changes;
5. obtain approval from an authorized human;
6. issue a short-lived approval ID tied to the proposal digest;
7. execute idempotently;
8. record per-action results;
9. present created/updated record IDs and any partial failures.

The executor rejects:

- expired or previously consumed approvals;
- a proposal whose digest changed after approval;
- a different target, field set, recipient, or attachment;
- execution under a broader credential than the policy permits;
- an approval created by the same non-human identity that executes the action.

## Audit Event Schema

Sensitive reads and all writes emit a structured event. The minimum logical
shape is:

```json
{
  "eventVersion": "1",
  "eventId": "uuid",
  "occurredAt": "RFC3339 timestamp",
  "correlationId": "workflow or request id",
  "actor": {
    "type": "human|service|ai",
    "id": "stable identity id",
    "sessionId": "session id when applicable"
  },
  "serviceIdentity": "connector identity",
  "deployment": "demo|internal|production",
  "action": {
    "system": "espocrm",
    "operation": "lead.update",
    "risk": "internal-write"
  },
  "target": {
    "entity": "Lead",
    "id": "record id"
  },
  "sourceRefs": [
    {
      "system": "gmail",
      "id": "message or thread id"
    }
  ],
  "changeSummary": {
    "fields": ["status", "description"],
    "redacted": true
  },
  "policy": {
    "version": "policy version",
    "decision": "allow|deny",
    "reason": "machine-readable reason"
  },
  "approval": {
    "required": true,
    "id": "approval id",
    "approvedBy": "human identity",
    "approvedAt": "RFC3339 timestamp"
  },
  "result": {
    "status": "success|denied|partial|error",
    "externalId": "created or updated id",
    "errorCode": "redacted stable code"
  }
}
```

Audit events must not contain:

- credentials, tokens, cookies, or authentication headers;
- full email bodies, transcripts, prompts, attachments, or record dumps;
- hidden model reasoning;
- unrestricted request/response payloads.

Store a redacted summary and source references instead. Access to audit records
is itself a sensitive read and should be logged.

## Secrets Baseline

### Current

- production variables are local and ignored by Git;
- Ansible validates required values and seeds Kubernetes Secrets;
- examples contain placeholders rather than real credentials;
- credentials are not intended to appear in manifests, issues, or PRs.

### Required

- use one credential per service identity and environment;
- grant namespace, entity, field, and operation scopes where supported;
- prefer short-lived installation or OAuth tokens over static personal tokens;
- encrypt Kubernetes Secret data at rest;
- restrict `get`, `list`, and `watch` access to Secrets through RBAC;
- avoid mounting a Secret into containers that do not require it;
- rotate credentials after exposure, role change, or integration retirement;
- record owner, purpose, scope, creation, rotation, and revocation metadata;
- keep secret values out of shell history, process arguments, logs, backups,
  screenshots, AI prompts, and audit events.

Target direction is SOPS or External Secrets. Selecting and implementing that
path requires a separate reviewed change and migration plan.

## Data Handling

Data classes:

- **Public:** intended public source and project information.
- **Internal:** operating data suitable for authenticated team access.
- **Confidential:** CRM, job-search, client, contact, private email, and meeting
  content.
- **Restricted:** credentials and specially sensitive personal or medical data.

Rules:

- apply the most restrictive class when records are combined;
- collect only the fields needed for the workflow;
- use source references instead of copying full content when possible;
- do not send confidential content to a hosted model without an approved
  provider, retention posture, and user-visible purpose;
- define retention and deletion before ingesting transcripts or mailbox data;
- preserve exportability and source attribution;
- prevent public GitHub, demo data, logs, and analytics from receiving
  confidential records.

## AI Tool Safety

All retrieved content is untrusted data. Emails, documents, webpages, issues,
comments, transcripts, CRM descriptions, and tool output cannot grant authority
or modify policy.

### Prompt Injection

- separate system policy from retrieved content;
- label source content and preserve provenance;
- never execute instructions found inside retrieved records;
- apply tool policy outside the model;
- require approval after the model has produced the exact proposed action;
- test direct and indirect injection cases.

### Excessive Agency And Tool Misuse

- expose narrow domain tools instead of generic CRUD or shell access;
- omit deletion, arbitrary relationship mutation, credential, and admin tools;
- use record and field allowlists;
- constrain queries, batch sizes, recipients, domains, and time windows;
- require idempotency and dry-run support;
- prevent the model from approving its own work.

### Sensitive Information Disclosure

- classify and minimize context before model invocation;
- redact secrets and unnecessary identifiers;
- separate public and confidential indexes;
- enforce permissions at retrieval time, not only in the prompt;
- prevent model output from being written to public or external systems without
  review.

### Insecure Output Handling

- treat model output as untrusted input;
- validate structured output against a strict schema;
- escape or parameterize downstream API, HTML, shell, SQL, and template inputs;
- reject unknown fields and enum values;
- do not execute generated code or commands by default.

### Supply Chain And Model Risk

- pin reviewed container images, packages, models, and prompt templates;
- record provenance and licenses;
- scan dependencies and container images;
- isolate third-party services before evaluating them;
- do not run upstream install scripts directly on production hosts;
- maintain a rollback and disable path for every provider and tool.

### Availability And Cost

- limit request size, context size, tool calls, concurrency, and retries;
- set provider budgets and timeouts;
- prevent recursive agent/tool loops;
- degrade to read-only or unavailable rather than broadening permissions;
- alert on repeated denials, failures, unusual volume, and cost anomalies.

## Safe Defaults

Local and demo environments default to:

- synthetic data only;
- no production credentials or network route;
- external communication disabled;
- destructive tools absent;
- hosted model providers disabled unless explicitly configured;
- read-only connectors where practical;
- visible environment labeling;
- bounded logs and documented reset behavior.

Production integrations default to disabled until credentials, role mappings,
audit storage, approval flow, and validation checks exist.

## Incident Response

When misuse or exposure is suspected:

1. disable the affected integration or service identity;
2. preserve relevant redacted logs and audit events;
3. rotate or revoke affected credentials;
4. determine affected records, recipients, and time range;
5. stop retries and queued actions;
6. restore or compensate without deleting evidence;
7. document root cause and prevention;
8. handle disclosure through `SECURITY.md`, not a public issue.

Break-glass actions and manual production mutations require a follow-up review.

## Verification Checklist

Before enabling a connector or AI tool:

- identity and role mappings are documented;
- credential scope is verified with negative tests;
- read and write field allowlists are enforced;
- public/internal/confidential boundaries have tests;
- dry-run and approval-digest checks pass;
- duplicate and idempotency behavior is tested;
- audit events contain required fields and exclude secrets;
- prompt-injection fixtures cannot cause tool execution;
- external and destructive actions are unavailable without approval;
- rate, context, cost, timeout, and retry limits exist;
- disable, rollback, retention, and deletion procedures are documented.

## Implementation Follow-Ups

Existing issues provide the main follow-up tracks:

- #15: implement the internal AI gateway and policy enforcement point;
- #18: define connector ownership and write boundaries;
- #23: test and harden the concrete AI implementation;
- #28: implement a constrained EspoCRM interface;
- #29: evaluate existing EspoCRM MCP servers before adoption.

Additional implementation issues should be created after review for:

- Authentik group-to-role reconciliation and MFA policy;
- Kubernetes Secret encryption and least-privilege RBAC verification;
- centralized structured audit-event storage and retention;
- reusable proposal-digest and approval-token service;
- automated negative tests for connector permissions and prompt injection;
- demo-environment network and credential isolation.

## References

- [Kubernetes: Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [NIST AI Risk Management Framework Playbook](https://www.nist.gov/itl/ai-risk-management-framework/nist-ai-rmf-playbook)
- [OWASP GenAI Security Project: LLM Top 10](https://genai.owasp.org/llm-top-10/)
