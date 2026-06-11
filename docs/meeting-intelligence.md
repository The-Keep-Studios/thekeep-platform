# Meeting Intelligence Design

This document defines a consent-first, self-hostable meeting-memory capability
for The Keep Platform. It starts with explicit transcript import rather than an
autonomous meeting bot.

The feature turns an approved transcript into portable meeting records:
summary, decisions, actions, open questions, and source-linked follow-up drafts.
Generated output remains a proposal until reviewed.

## Initial Ingestion Decision

The first implementation should accept an operator-selected transcript through:

1. Markdown or plain-text file upload;
2. JSON API import from an approved capture/export tool;
3. a local command that submits one file to the internal API.

The first version should not:

- join meetings automatically;
- record audio or video;
- depend on a Chrome extension;
- monitor microphone or browser activity;
- ingest an entire Drive, mailbox, or calendar;
- create tasks, CRM records, or GitHub issues automatically.

Why this path:

- participant notice and source selection remain visible to the user;
- transcript storage and deletion behavior can be tested independently from
  capture technology;
- Vexa, Amurex, desktop capture, or vendor exports can later implement one
  stable ingestion contract;
- local fixtures can exercise the complete pipeline without real meetings.

## User Experience

### Before Ingestion

The import screen or CLI must show:

- meeting title and source;
- meeting date and timezone;
- organizer and importing user;
- participant names only when needed;
- consent/notice confirmation;
- data classification;
- retention selection;
- project, organization, or private-workspace destination;
- provider choice and whether content leaves the local deployment.

Import is blocked until required consent and retention fields are provided.

### During Processing

The user sees:

- upload/import progress;
- selected provider and processing location;
- current phase: validate, store source, summarize, extract, review;
- clear failure state without duplicate imports;
- a cancel option before external provider submission.

### Review

The review screen separates:

- source transcript;
- generated summary;
- decisions;
- action items;
- open questions;
- proposed links and follow-up drafts.

Every generated item can be edited, accepted, rejected, or marked uncertain.
No item is written to another system from the initial workflow.

### After Review

The user can:

- export the meeting record as Markdown and JSON;
- delete generated output while retaining the source;
- delete source and derived output together;
- reprocess with a new prompt/model while keeping version history;
- propose downstream tasks or issues through a later approval workflow.

## Canonical Storage Model

The canonical record should live in a dedicated meeting-memory service or
database, not in the AI gateway, Leantime, CRM, or a vector store.

Core entities:

### Meeting

```json
{
  "id": "uuid",
  "title": "Weekly product review",
  "startedAt": "2026-06-11T14:00:00-04:00",
  "endedAt": "2026-06-11T14:45:00-04:00",
  "timezone": "America/New_York",
  "classification": "internal",
  "sourceType": "manual-upload",
  "sourceId": "optional-stable-source-id",
  "sourceUrl": null,
  "organizer": {
    "displayName": "Example Person"
  },
  "participants": [],
  "consent": {
    "basis": "participant-notice-confirmed",
    "confirmedBy": "user-id",
    "confirmedAt": "RFC3339 timestamp",
    "noticeVersion": "1"
  },
  "retention": {
    "policy": "delete-after-90-days",
    "deleteAt": "RFC3339 timestamp"
  },
  "createdBy": "user-id",
  "createdAt": "RFC3339 timestamp"
}
```

### Transcript

```json
{
  "id": "uuid",
  "meetingId": "uuid",
  "version": 1,
  "language": "en",
  "format": "text",
  "contentHash": "sha256",
  "storageRef": "internal-object-reference",
  "speakerLabels": "provided|inferred|none",
  "sourceMetadata": {},
  "createdAt": "RFC3339 timestamp"
}
```

Transcript content should be encrypted at rest, excluded from normal logs, and
stored outside the vector/search index. The index contains derived chunks and
source references governed by the same permissions and deletion policy.

### Processing Run

```json
{
  "id": "uuid",
  "meetingId": "uuid",
  "transcriptVersion": 1,
  "workflowVersion": "meeting-summary-v1",
  "promptVersion": "1",
  "provider": "localai",
  "model": "configured-model-id",
  "status": "queued|running|review|accepted|failed",
  "startedAt": "RFC3339 timestamp",
  "completedAt": null,
  "errorCode": null
}
```

### Meeting Record

```json
{
  "id": "uuid",
  "meetingId": "uuid",
  "processingRunId": "uuid",
  "version": 1,
  "status": "draft|reviewed|superseded",
  "summary": "Concise reviewed summary.",
  "decisions": [],
  "actions": [],
  "openQuestions": [],
  "topics": [],
  "links": [],
  "reviewedBy": null,
  "reviewedAt": null
}
```

## Derived Schemas

### Decision

```json
{
  "id": "uuid",
  "statement": "Use explicit transcript import for the first release.",
  "status": "proposed|confirmed|reversed",
  "owner": null,
  "effectiveDate": null,
  "source": {
    "transcriptVersion": 1,
    "startOffsetSeconds": 120,
    "endOffsetSeconds": 155,
    "excerpt": "Short supporting excerpt."
  },
  "confidence": "high|medium|low"
}
```

### Action

```json
{
  "id": "uuid",
  "title": "Draft the import API contract",
  "description": null,
  "owner": {
    "displayName": "Example Person",
    "linkedRecord": null
  },
  "dueDate": null,
  "status": "proposed|accepted|rejected|completed",
  "destinationProposal": null,
  "source": {
    "transcriptVersion": 1,
    "startOffsetSeconds": 300,
    "endOffsetSeconds": 325
  },
  "confidence": "medium"
}
```

### Open Question

```json
{
  "id": "uuid",
  "question": "Which storage backend should hold encrypted transcript objects?",
  "owner": null,
  "dueDate": null,
  "status": "open|answered|dismissed",
  "source": {
    "transcriptVersion": 1,
    "startOffsetSeconds": 410,
    "endOffsetSeconds": 435
  }
}
```

Generated facts must retain source offsets or equivalent citations. A summary
without traceable evidence is useful prose, not a reliable organizational
record.

## Portable Markdown Export

```markdown
---
meeting_id: uuid
meeting_date: 2026-06-11
classification: internal
record_version: 1
source_type: manual-upload
---

# Weekly Product Review

## Summary

Reviewed summary.

## Decisions

- [Confirmed] Use explicit transcript import for the first release.

## Actions

- [ ] Example Person: Draft the import API contract.

## Open Questions

- Which storage backend should hold encrypted transcript objects?

## Provenance

- Transcript version: 1
- Processing workflow: meeting-summary-v1
- Reviewed by: user-id
```

The export excludes raw transcript content by default. A separate explicit
export may include it.

## Ingestion Contract

Logical request:

```json
{
  "idempotencyKey": "source-and-content-hash",
  "meeting": {
    "title": "Weekly product review",
    "startedAt": "RFC3339 timestamp",
    "timezone": "America/New_York",
    "classification": "internal"
  },
  "transcript": {
    "format": "text",
    "language": "en",
    "content": "transcript text"
  },
  "consent": {
    "basis": "participant-notice-confirmed",
    "noticeVersion": "1"
  },
  "retentionPolicy": "delete-after-90-days"
}
```

Requirements:

- maximum upload size and transcript duration are explicit;
- UTF-8 and supported formats are validated;
- content hash and source ID prevent duplicate ingestion;
- caller is authorized for the selected destination;
- transcript content is never included in request logs;
- processing is asynchronous and returns a stable job ID;
- failed jobs can retry without creating duplicate meetings;
- provider routing follows classification policy from #15 and #20.

## Consent Requirements

The product should make consent visible and easy rather than rely on a buried
policy.

Required UX:

- pre-meeting notice templates for calendar descriptions and spoken notice;
- import-time confirmation that notice/consent requirements were satisfied;
- meeting-level record of the notice version and confirming user;
- a participant-request workflow for access, correction, export, or deletion;
- clear indication when audio, transcript, or generated summaries are retained;
- no covert capture mode.

Example notice:

> This meeting may be transcribed to produce internal notes, decisions, and
> action items. The transcript is access-controlled and retained according to
> our meeting-data policy. Tell the organizer if you object or need an
> alternative.

This is a product requirement, not legal advice. Recording and consent laws vary
by location, participant, and context. The maintainer must obtain appropriate
legal guidance before enabling automated capture for external or client
meetings.

## Retention And Deletion

Initial policy choices:

- default transcript retention: 90 days;
- default reviewed meeting-record retention: until manually deleted;
- raw audio/video: not accepted or stored;
- raw AI prompts/responses: not retained by the gateway;
- processing metadata and redacted audit events: follow the security baseline;
- demo records: resettable synthetic data only.

Deletion behavior:

1. mark the meeting pending deletion;
2. stop processing and downstream proposals;
3. remove transcript objects and derived search chunks;
4. delete generated drafts and exports owned only by the meeting store;
5. retain a minimal redacted deletion audit event;
6. report linked records in other canonical systems for separate reviewed
   deletion or unlinking;
7. account for backup expiration and document the maximum recovery window.

Changing retention defaults requires maintainer review and should not silently
extend existing records.

## Permissions

Minimum capabilities:

```text
meeting:create
meeting:read
meeting:delete
transcript:read
record:generate
record:review
record:export
record:propose_link
```

Permissions apply per workspace/project and classification. A user who may view
a summary does not automatically receive transcript access.

## Downstream Links

The meeting store may retain links to:

- Leantime project/task IDs;
- GitHub issue/PR URLs;
- EspoCRM Account, Contact, Lead, or Opportunity IDs;
- Baserow person/organization IDs;
- future knowledge-memory record IDs.

The meeting service does not update those systems directly in the first
release. Later connectors create proposals with exact target and field changes,
using the approval model from #15 and #20.

## Search And Knowledge Memory

Only reviewed meeting records enter normal knowledge search by default.
Transcript search is a separate permission and index.

Index entries include:

- meeting and record IDs;
- reviewed summary/decision/action text;
- source version;
- classification;
- access-control attributes;
- deletion/retention state;
- canonical source URL.

Deletion removes all corresponding chunks. Reindexing is deterministic and does
not create a second canonical copy.

## First Proof Of Concept

Create a follow-up implementation issue for:

**Manual transcript import to reviewed Markdown record**

Scope:

- local-only service or CLI;
- synthetic transcript fixture;
- JSON ingestion validation;
- idempotent meeting/transcript storage;
- LocalAI-compatible summary workflow;
- strict summary/decision/action/question schema;
- review state;
- Markdown/JSON export;
- deletion and reindex verification;
- no write integrations.

Acceptance evidence:

- duplicate imports return the same meeting ID;
- malformed and oversized transcripts fail safely;
- generated items include source citations;
- rejected generated items do not appear in reviewed export;
- deleting the fixture removes transcript and search data;
- logs and audit events contain no transcript body;
- no production or confidential data is used.

## Capture Backends

Vexa (#24), Amurex (#25), desktop capture, and provider exports are adapters to
the ingestion contract, not owners of meeting memory.

Before enabling a capture backend, evaluate:

- browser/platform dependency;
- visible participant notice;
- bot identity and meeting admission behavior;
- audio/transcript routing;
- authentication and tenant isolation;
- provider and analytics data flows;
- update and supply-chain path;
- resource requirements;
- retry and duplicate behavior;
- deletion and retention controls.

## Open Decisions

- canonical database and encrypted object-storage backend;
- whether 90 days is the correct default transcript retention;
- whether external/client meetings require a separate workspace and policy;
- initial LocalAI model and quality threshold;
- participant self-service access/deletion mechanism;
- whether reviewed decisions/actions are immutable versions or editable current
  records;
- identity matching for participant names and downstream people records.
