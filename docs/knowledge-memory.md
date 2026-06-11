# Knowledge Memory Design

This document defines a permission-aware, exportable organizational memory
layer for The Keep Platform.

The memory layer is an index and retrieval system over canonical source
records. It is not a new system of record and not a vector-only data store.

## Goals

- make approved organizational knowledge searchable across systems;
- preserve source attribution and update history;
- enforce source permissions at indexing and query time;
- keep public, internal, confidential, and restricted data separated;
- export records as readable Markdown and JSON;
- combine lexical and semantic retrieval;
- support deterministic reindexing and deletion;
- return citations with every answer or result.

## Non-Goals

- copying every record from every system;
- replacing GitHub, Leantime, EspoCRM, Baserow, Gmail, or meeting storage;
- unrestricted mailbox or CRM ingestion;
- using embeddings as the canonical representation;
- granting an assistant broader access than the requesting user;
- automatic writes back to source systems;
- indexing credentials, session material, or restricted medical data.

## Source Connector List

Connectors are enabled individually and declare record/field allowlists.

### Phase 1

| Source | Initial scope | Classification | Notes |
| --- | --- | --- | --- |
| Repository Markdown | Allowlisted public docs and runbooks | Public/Internal | File path and commit SHA are source identity |
| GitHub | Allowlisted issues, PRs, comments, and merged metadata | Public | Read-only first prototype |
| Meeting records | Reviewed summaries, decisions, actions, and questions | Internal/Confidential | Raw transcripts use separate permission and index |

### Phase 2

| Source | Initial scope | Classification | Notes |
| --- | --- | --- | --- |
| Leantime | Allowlisted projects/tasks/comments | Internal/Confidential | Client-specific data remains private |
| Baserow | Approved relationship/organization records | Confidential | Field-level allowlist required |
| EspoCRM | Approved Leads, Opportunities, Accounts, Contacts, Tasks | Confidential | Active pipeline remains canonical in EspoCRM |

### Deferred

| Source | Reason |
| --- | --- |
| Gmail | High-volume confidential content; begin with explicit referenced messages, not mailbox sync |
| Raw meeting transcripts | Higher consent and retention burden than reviewed records |
| Attachments | Malware, format, copyright, and data-minimization concerns |
| Production logs | Operational search belongs in Loki; only reviewed incident records enter memory |
| Restricted rescue/medical data | Outside the initial platform-memory risk tolerance |

## Canonical Memory Record

Every indexed item is represented as a portable record:

```json
{
  "schemaVersion": "1",
  "id": "memory-record-uuid",
  "source": {
    "system": "github",
    "repository": "The-Keep-Studios/thekeep-platform",
    "entity": "issue",
    "id": "16",
    "url": "https://github.com/example/repository/issues/16",
    "version": "source-version-or-updated-at",
    "observedAt": "RFC3339 timestamp"
  },
  "record": {
    "type": "issue",
    "title": "Meeting Intelligence",
    "summary": "Human-readable source-derived summary.",
    "bodyMarkdown": "Portable normalized content.",
    "status": "open",
    "authors": ["source-actor-id"],
    "createdAt": "RFC3339 timestamp",
    "updatedAt": "RFC3339 timestamp",
    "tags": ["meeting-intelligence"],
    "links": []
  },
  "access": {
    "classification": "public",
    "workspaceId": "public",
    "principals": [],
    "groups": ["public"],
    "policyVersion": "1"
  },
  "indexing": {
    "contentHash": "sha256",
    "connectorVersion": "connector-version",
    "indexedAt": "RFC3339 timestamp",
    "deletedAt": null
  }
}
```

Requirements:

- `source.system`, `source.entity`, and `source.id` form a stable source key;
- source version and content hash make updates deterministic;
- `bodyMarkdown` remains understandable without the index;
- links identify related records without transferring ownership;
- access attributes travel with every chunk and retrieval result;
- deleted records become tombstones until derivative data is removed.

## Markdown Export

```markdown
---
memory_record_id: memory-record-uuid
source_system: github
source_entity: issue
source_id: "16"
source_url: https://github.com/example/repository/issues/16
source_version: source-version
classification: public
indexed_at: RFC3339 timestamp
---

# Meeting Intelligence

Human-readable normalized content.

## Source

- System: GitHub
- Record: issue 16
- Last observed: RFC3339 timestamp
```

Exports preserve provenance and classification. They do not include embeddings.

## Storage Layers

### Record Store

The record store contains canonical normalized memory records and connector
state. Initial direction:

- dedicated PostgreSQL database;
- JSONB for source-specific metadata and access attributes;
- normalized columns for source key, classification, workspace, timestamps,
  content hash, and deletion state;
- immutable source-version history where storage cost permits;
- encrypted persistent storage and application-level access controls.

### Search Index

Initial direction is hybrid PostgreSQL search:

- PostgreSQL full-text search for exact terms, names, identifiers, and phrases;
- `pgvector` for semantic similarity;
- reciprocal-rank or weighted fusion to combine lexical and vector results;
- explicit filters for workspace, classification, source, entity, and time;
- separate embedding rows by chunk and embedding-model version.

Why this direction:

- one operational database for the initial scale;
- portable open-source components;
- transactional update/tombstone behavior;
- readable records remain available if vector generation fails;
- avoids adding a distributed vector service before scale requires it.

Reconsider a dedicated search/vector backend only when measured corpus size,
latency, isolation, or availability requirements exceed PostgreSQL.

### Object Storage

Large source documents and raw transcripts remain in their canonical stores or
approved encrypted object storage. The memory database stores references and
normalized text needed for the approved index.

## Chunking And Embeddings

Chunking is deterministic per record type:

- preserve headings and list boundaries;
- keep source record and section IDs;
- avoid combining records or security classifications;
- cap chunk size with overlap only within one source section;
- store chunk text hash and ordinal;
- regenerate when source, chunker, or normalization version changes.

Embedding rules:

- model is configured per classification;
- confidential chunks cannot use an unapproved hosted embedding provider;
- embedding model/version is stored with each vector;
- failed embedding leaves lexical search available;
- model changes create a new index generation before old vectors are removed.

## Permission Model

Permission is enforced before and after search.

### Index-Time

The connector:

- authenticates with a dedicated read identity;
- retrieves only allowed entities and fields;
- assigns classification and workspace;
- records source permissions or approved group mappings;
- rejects records with unknown classification;
- never indexes secrets or restricted fields.

### Query-Time

The retrieval service:

1. validates the requesting principal;
2. resolves permitted workspaces, groups, classifications, sources, and fields;
3. applies filters in the database query;
4. retrieves only authorized candidate chunks;
5. reranks only those candidates;
6. returns citations and access metadata;
7. audits sensitive retrieval.

Prompt instructions cannot change query filters.

### Result-Time

Before returning results:

- recheck current source permission for high-risk sources when practical;
- remove fields not allowed for the caller;
- cap result and content size;
- preserve classification in the response;
- prevent caching across principals or workspaces;
- avoid leaking the existence of unauthorized records through counts or errors.

## Retrieval API

Logical query:

```json
{
  "query": "What did we decide about transcript ingestion?",
  "sources": ["github", "meeting-records"],
  "recordTypes": ["issue", "decision"],
  "workspaceId": "internal",
  "classificationMax": "confidential",
  "timeRange": null,
  "limit": 10
}
```

Logical result:

```json
{
  "results": [
    {
      "recordId": "memory-record-uuid",
      "chunkId": "chunk-uuid",
      "title": "Meeting Intelligence",
      "excerpt": "The first implementation should accept an operator-selected transcript...",
      "score": 0.91,
      "source": {
        "system": "github",
        "entity": "issue",
        "id": "16",
        "url": "https://github.com/example/repository/issues/16"
      },
      "classification": "public",
      "updatedAt": "RFC3339 timestamp"
    }
  ]
}
```

The API accepts a maximum classification as a narrowing input only. It cannot
elevate the caller above policy.

## Indexing Workflow

### Initial Index

1. connector lists records within its configured scope;
2. normalize and classify each record;
3. calculate source version and content hash;
4. write/update the memory record;
5. create deterministic chunks;
6. write lexical-search representation;
7. generate approved embeddings;
8. mark the connector cursor only after the batch commits;
9. emit counts and redacted audit evidence.

### Incremental Update

- use source update timestamps, cursors, webhooks, or commit SHAs;
- compare source version and content hash;
- skip unchanged records;
- create a new normalized version before replacing active chunks;
- preserve source attribution;
- use idempotency keys for every batch.

### Deletion

- record a source tombstone;
- remove active chunks and vectors in the same logical operation;
- invalidate caches;
- retain only minimal redacted indexing/audit evidence;
- verify deletion by source key;
- account for backup expiration.

### Reindex

Reindex is generation-based:

1. create a new generation for a connector/chunker/embedding version;
2. build alongside the active generation;
3. validate counts, permissions, citations, and sample queries;
4. atomically activate the new generation;
5. retain the old generation for a bounded rollback window;
6. delete the old generation after validation.

Reindexing never broadens source scope automatically.

## Deduplication

Deduplication layers:

1. exact source key identifies the same canonical record;
2. content hash identifies unchanged or exact duplicate content;
3. canonical URL or external ID identifies known cross-references;
4. fuzzy similarity produces manual-review candidates only.

Records from different canonical systems are not silently merged. A GitHub
issue and Leantime task may describe the same work but have different ownership,
permissions, and lifecycle.

## Read-Only Assistant Prototype

Create a follow-up implementation issue for:

**Cited public repository assistant**

Scope:

- index allowlisted public Markdown files and GitHub issues/PRs;
- use PostgreSQL full-text search first;
- add `pgvector` only after lexical ingestion/reindexing is reliable;
- answer through the #15 gateway with citations;
- no confidential sources and no write tools;
- synthetic injection fixtures in indexed content.

Acceptance evidence:

- every answer cites source URL and record version;
- changed source is reflected after incremental indexing;
- deleted source disappears from search;
- reindex can switch generations and roll back;
- prompt injection in source text cannot cause a tool call;
- unknown repositories and paths are rejected;
- index and audit logs contain no credentials;
- Markdown/JSON export recreates readable records without embeddings.

## Operational Requirements

- connector, indexing, embedding, and query metrics;
- alerts for stale cursors, failed batches, permission errors, deletion backlog,
  and embedding failures;
- per-source rate limits and exponential backoff;
- database backups and restore verification;
- migration and rollback for record/schema changes;
- health checks that distinguish lexical search from embedding availability;
- admin views for connector scope, cursor, generation, record counts, failures,
  and deletion status;
- kill switch per source connector and embedding provider.

## Security And Privacy Tests

- unauthorized workspace returns no records or counts;
- restricted field never appears in chunks or audit logs;
- changing group membership invalidates cached access;
- public and confidential indexes cannot cross-query;
- malicious source instructions remain quoted data;
- hosted embedding fallback is denied for confidential records;
- deletion removes all chunks, vectors, and cache entries;
- connector credentials cannot write to the source system;
- oversized and malformed source records fail without stopping other records;
- source URLs and excerpts are escaped before UI rendering.

## Open Decisions

- PostgreSQL deployment and backup ownership;
- full-text language configuration;
- initial local embedding model and quality threshold;
- whether confidential sources need physically separate databases or schemas;
- maximum retention for normalized historical versions;
- which source permissions require live recheck at query time;
- whether the first assistant uses only lexical search or hybrid search;
- expected corpus size and latency targets that would trigger a dedicated
  search backend.
