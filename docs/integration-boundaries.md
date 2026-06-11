# Integration Boundaries

The Keep Platform uses several focused systems rather than one application for
every workflow. Integrations should reduce duplicate entry without erasing
ownership boundaries or spreading confidential data into unnecessary systems.

This document defines the default ownership and automation policy for GitHub,
Leantime, EspoCRM, Baserow, and Gmail.

## Principles

1. Every record type has one canonical system of record.
2. Read access does not imply write access.
3. A connector receives only the fields and records required for its use case.
4. Cross-system copies retain source attribution and a stable source ID.
5. Writes are proposed and reviewed before they are executed unless a narrowly
   scoped workflow has been explicitly approved.
6. Deletion, external communication, and public publication always require
   direct human approval.
7. Integrations fail closed when identity, scope, approval, or destination is
   ambiguous.
8. Bidirectional synchronization is not the default.

## Data Classification

| Class | Examples | Default handling |
| --- | --- | --- |
| Public | Public GitHub issues, merged pull requests, public docs | May be indexed and summarized |
| Internal | Leantime tasks, runbooks, non-sensitive meeting summaries | Authenticated internal access only |
| Confidential | CRM pipeline, contacts, job search, client plans, private email | Least privilege; no public copies |
| Restricted | Credentials, private keys, session cookies, medical or other specially sensitive records | Never ingest into assistant memory or logs |

When a record combines classifications, apply the most restrictive class.

## Canonical Ownership

| Record type | Canonical system | Permitted references elsewhere |
| --- | --- | --- |
| Public roadmap and implementation issue | GitHub | Leantime execution task may link to it |
| Source code, review, release evidence | GitHub | Read-only summaries in internal memory |
| Private execution task and timebox | Leantime | Link to public GitHub issue when appropriate |
| Client-specific implementation detail | Leantime | CRM link or private memory reference only |
| Active job, sales, consulting, client, or publishing pursuit | EspoCRM | Leantime follow-up task may reference record ID |
| Recruiter, hiring manager, client, or active sales contact | EspoCRM | Baserow may reference only when relationship-memory use is distinct |
| General relationship and organization memory | Baserow | Link to EspoCRM when an active opportunity exists |
| Email message | Gmail, with Espo Email when deliberately imported | Store a reference or evidence summary, not uncontrolled copies |
| Meeting transcript and derived decision record | Future meeting-memory store | Link to projects, people, and source systems |
| Authentication identity and access policy | Authentik plus application authorization | Do not copy credentials into business systems |

A copied title, summary, or link is not a transfer of canonical ownership.

## System Boundaries

### GitHub

GitHub owns public engineering intent and evidence.

Allowed reads:

- public issues, pull requests, comments, reviews, commits, and documentation;
- repository metadata needed to determine issue and PR state;
- private repository content only through an explicitly scoped credential.

Approval-gated writes:

- create a draft issue or pull request;
- push a focused issue branch;
- add a progress or validation comment;
- update a draft description with current evidence.

Direct human approval required:

- merge or approve a pull request;
- close or reopen an issue;
- publish a release;
- change branch protection, Actions secrets, repository access, or settings;
- post confidential evidence.

### Leantime

Leantime owns private execution and workload management.

Allowed reads:

- project, milestone, task, status, assignee, due date, and dependency data
  needed for an approved internal workflow;
- comments and activity when required to understand task state.

Approval-gated writes:

- create or update a task from an approved GitHub issue or CRM follow-up;
- add an internal progress note with source attribution;
- change a task status when the underlying event is verified.

Direct human approval required:

- delete projects, tasks, comments, or attachments;
- bulk reassign or reschedule work;
- expose private task content in GitHub or another public destination.

### EspoCRM

EspoCRM owns active opportunities and the people and organizations directly
involved in those pursuits.

Allowed reads:

- search Leads, Opportunities, Accounts, Contacts, Tasks, and relevant Emails;
- retrieve field metadata and allowed enum values;
- check for duplicates before proposing a create or update;
- read only the fields required for the approved workflow.

Approval-gated writes:

- create or update a Lead after a dry-run review;
- promote a Lead to an Opportunity only after reciprocal signal or explicit
  override;
- create a linked follow-up Task;
- add source attribution and an assistant-generated audit note.

Prohibited assistant actions:

- delete CRM records;
- auto-apply to jobs;
- send unsolicited recruiter, employer, client, or publisher messages;
- create an Opportunity from a cold or scraped item without reciprocal signal;
- expose job-search, client, or contact data in public GitHub artifacts.

Issue #28 defines the intended constrained assistant surface. Issue #29 must
evaluate existing MCP implementations before one is trusted with these writes.

### Baserow

Baserow owns lower-pressure relationship and organization memory.

Allowed reads:

- retrieve approved people, organization, interaction, and relationship context;
- search for duplicate people and organizations;
- export a scoped record set for a reviewed internal workflow.

Approval-gated writes:

- create or update a relationship-memory record from an approved source;
- append an interaction summary that identifies its origin;
- link a relationship record to an EspoCRM record without copying the entire
  active pipeline.

Direct human approval required:

- bulk merge, delete, or reclassify records;
- import a new external dataset;
- expose records outside the confidential deployment.

### Gmail

Gmail is a communication source, not the canonical system of record for project,
CRM, or relationship state.

Allowed reads:

- search a narrowly scoped mailbox query for an approved workflow;
- retrieve message subject, date, participants, thread ID, and required body
  content;
- distinguish automated confirmations from human replies;
- prepare evidence summaries with a Gmail source reference.

Approval-gated writes:

- create a draft reply or outreach message;
- apply a narrowly defined label when the workflow explicitly includes it.

Direct human approval required:

- send a message;
- add recipients or attachments;
- delete, archive, forward, or broadly relabel messages;
- perform unrestricted mailbox ingestion.

Email bodies and attachments should not be copied wholesale into GitHub,
assistant logs, or long-lived memory when a source reference and concise summary
are sufficient.

## Automation Levels

Every connector action must be assigned one level:

| Level | Meaning | Default |
| --- | --- | --- |
| Read | Retrieve a scoped record without mutation | Allowed when authorized |
| Propose | Produce a dry run, draft, or patch | Preferred for all writes |
| Approve | Human selects the exact proposed actions | Human only |
| Execute | Apply the approved actions and return IDs/results | Narrowly scoped |
| Prohibited | Delete, publish, send, merge, or cross a protected boundary | Not available to assistants |

An approval is bound to the proposed target, fields, and values. It is not a
general permission to perform additional writes.

## Connector Contract

Before implementation, each connector must define:

- actor and credential identity;
- canonical source and destination;
- record and field allowlists;
- data classification;
- query and result limits;
- duplicate and idempotency keys;
- dry-run representation;
- approval identifier and expiry;
- audit event format;
- retry and partial-failure behavior;
- deletion and retention behavior;
- rollback or compensating action;
- rate limits and backoff;
- operator-visible logs and metrics.

Credentials must be scoped per connector and environment. A shared administrator
credential is not an acceptable shortcut.

## Source Attribution And Identity

Cross-system references should include:

- source system;
- source record or thread ID;
- source URL when safe;
- source timestamp;
- import or connector version;
- last observed source update;
- human or service actor responsible for the write.

Use stable source IDs for idempotency. Fuzzy text matching may identify
duplicates for review, but it must not silently merge records.

## Audit Requirements

Every assistant-originated write must record:

- actor and credential identity;
- requesting workflow and correlation ID;
- source records consulted;
- target system, entity, and record ID;
- proposed field changes;
- approval actor, time, and approval ID;
- execution time and result;
- error or partial-failure details;
- a redacted summary suitable for incident review.

Secrets and full confidential payloads do not belong in the audit event.

## First Prototype

The first integration prototype should be a read-only GitHub knowledge
connector:

1. ingest public issues, pull requests, and selected Markdown documents;
2. preserve repository, URL, record ID, author, timestamps, and update state;
3. emit portable Markdown or JSON records;
4. perform no GitHub writes;
5. demonstrate reindexing and source-update handling;
6. enforce a repository allowlist.

This path exercises attribution, canonical records, incremental indexing, and
permission boundaries without exposing private CRM or mailbox data.

After that foundation is reviewed, the next prototype should be EspoCRM
read/search plus dry-run Lead preparation. It must not enable writes until the
security baseline in #20 and the MCP evaluation in #29 are accepted.

## What Stays Out Of Public GitHub

- client names, requirements, credentials, and private delivery details;
- job applications, recruiter conversations, compensation details, and personal
  pipeline state;
- private contacts, email bodies, attachments, and relationship notes;
- Leantime workload details that reveal private capacity or client work;
- production URLs or topology details that are not already intentionally public;
- vulnerability reproduction details before responsible disclosure;
- raw AI prompts or tool logs containing internal records.

Use synthetic examples when public documentation needs to show a workflow.

## Failure And Recovery

- Reads should be retryable and side-effect free.
- Writes require idempotency keys so a retry cannot create duplicates.
- Partial batches stop and report per-record results; they do not continue
  silently after an authorization or schema error.
- Connectors must not reinterpret a rejected or expired approval.
- Rollback should prefer a compensating update that preserves history over
  deletion.
- When source and destination conflict, do not overwrite either automatically;
  produce a manual-review item.

## Non-Goals

- universal bidirectional synchronization;
- copying all records into a central database;
- using Gmail as a project or CRM database;
- giving an AI assistant unrestricted browser automation;
- automatic external communication;
- autonomous deletion or record merging;
- exposing confidential systems through public GitHub artifacts.
