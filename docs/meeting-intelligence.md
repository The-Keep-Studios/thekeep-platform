# Meeting Intelligence

Start with explicit transcript import, not an autonomous meeting bot. Stabilize
consent, storage, review, deletion, and export before adding Vexa, Amurex, or
another capture backend.

## First Workflow

1. User selects one Markdown/text file or approved API export.
2. UI/CLI requires title, date/timezone, classification, consent confirmation,
   retention, and destination.
3. Service validates size/format and deduplicates by source ID/content hash.
4. AI produces a draft summary, decisions, actions, and open questions.
5. User accepts, edits, rejects, or marks each item uncertain.
6. Reviewed record exports to Markdown/JSON.
7. Downstream tasks/issues remain proposals requiring separate approval.

No automatic meeting join, audio/video storage, mailbox/Drive ingestion, or
write integration in the first release.

## Storage

Use a dedicated meeting-memory store. The AI gateway is processing
infrastructure, not the system of record.

| Entity | Essential fields |
| --- | --- |
| Meeting | ID, title, time/timezone, classification, source, participants, consent, retention, creator |
| Transcript | Meeting ID, version, language, content hash, encrypted storage reference, speaker-label source |
| Processing run | Transcript/workflow/prompt/provider/model versions, status, timestamps, error code |
| Meeting record | Version, review status, summary, decisions, actions, questions, reviewer |

Large/raw content stays in encrypted object storage. Search indexes contain
approved derived text plus source/access metadata.

## Derived Record Contract

Each decision/action/question includes:

- stable ID;
- statement/title;
- proposed/reviewed status;
- owner and due date when present;
- transcript version and source offset/citation;
- confidence or uncertainty.

A generated statement without source evidence is draft prose, not reliable
organizational memory.

## Portable Export

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
- [Confirmed] Use explicit transcript import first.

## Actions
- [ ] Owner: Draft the import API.

## Open Questions
- Which encrypted object store should hold transcripts?
```

Raw transcript content is excluded by default and exported only explicitly.

## Ingestion Contract

The request contains:

- idempotency key;
- meeting metadata;
- transcript format/language/content;
- consent basis and notice version;
- retention policy.

Requirements:

- strict size/format limits;
- no transcript bodies in request logs;
- stable async job ID;
- safe retry without duplicate meeting creation;
- provider routing by classification;
- caller authorization for destination;
- cancel before external provider submission.

## Consent And User Experience

The product must provide:

- pre-meeting written/spoken notice templates;
- import-time confirmation and notice version;
- visible indication of retained transcript/summary data;
- participant access/correction/export/deletion workflow;
- no covert capture mode.

Example:

> This meeting may be transcribed for internal notes, decisions, and actions.
> Tell the organizer if you object or need an alternative.

This is a product requirement, not legal advice. Recording/consent law varies;
obtain appropriate review before automated external/client capture.

## Retention

Initial proposal:

- transcript: 90 days;
- reviewed meeting record: until manually deleted;
- raw audio/video: never stored;
- raw AI prompt/response: not retained by the gateway;
- audit metadata: security-policy retention.

Deletion stops processing, removes transcript objects/search chunks/derived
drafts, invalidates caches, and leaves only redacted audit evidence. Linked
records in other canonical systems are reported for separate review, not
silently deleted.

## Permissions

Separate capabilities for meeting create/read/delete, transcript read, record
generate/review/export, and downstream-link proposal. Summary access does not
automatically grant transcript access.

Only reviewed meeting records enter normal knowledge search. Transcript search
uses a separate permission and index.

## Proof Of Concept

Create a focused implementation issue for **manual transcript import to reviewed
Markdown record**:

- local-only service/CLI and synthetic fixture;
- idempotent JSON import;
- LocalAI-compatible structured extraction;
- review state and Markdown/JSON export;
- deletion/reindex verification;
- no write integrations.

Evidence:

- duplicate import returns the same meeting ID;
- malformed/oversized input fails safely;
- generated items cite source offsets;
- rejected items stay out of reviewed export;
- deletion removes transcript and search data;
- logs/audit contain no transcript body.

## Capture Backends

Vexa (#24), Amurex (#25), desktop capture, and vendor exports are adapters to
this ingestion contract. Evaluate consent visibility, bot admission, auth,
tenant isolation, analytics/data flow, retention, resources, updates, and
duplicate behavior before enabling any backend.

## Decisions Needed

- encrypted object/database backend;
- 90-day transcript default;
- separate policy/workspace for external meetings;
- initial local model and quality threshold;
- participant self-service;
- immutable versions versus editable current records.
