# Contributing

The Keep Platform is both an operating platform and a public engineering
project. Contributions should make the intent, risk, and operational impact of
a change understandable without exposing private internal data.

## Where Work Belongs

Use public GitHub issues for:

- bugs that can be described without secrets or private records;
- architecture and implementation proposals;
- installability, documentation, testing, and reliability work;
- public roadmap and integration-boundary decisions;
- upstream research and reproducible technical findings.

Do not put the following in public GitHub issues, pull requests, logs, or
fixtures:

- credentials, tokens, private keys, cookies, kubeconfigs, or secret values;
- client-specific implementation details or confidential commercial plans;
- personal job-search, CRM, contact, rescue, adopter, foster, or medical data;
- production database contents, exports, backups, or screenshots containing
  private records;
- undisclosed security vulnerabilities.

Private execution planning and sensitive implementation details belong in
Leantime. Active job, sales, client, and publishing opportunities belong in
EspoCRM. Relationship and organization memory belongs in Baserow. Gmail is a
communication source, not the canonical project tracker.

Report vulnerabilities according to [`SECURITY.md`](SECURITY.md), not in a
public issue.

## Issue Titles

Use a stable category prefix so the backlog remains scannable before a larger
label taxonomy is justified:

| Prefix | Use |
| --- | --- |
| `Bug:` | Reproducible incorrect behavior |
| `Security:` | Public hardening work without vulnerability details |
| `Architecture:` | System boundaries and durable technical direction |
| `Roadmap:` | Planning model, sequencing, and capability tracks |
| `Installability:` | Bootstrap, local development, and onboarding |
| `Demo Mode:` | Synthetic public demo experience and isolation |
| `Integrations:` | Ownership and contracts between systems |
| `AI Services:` | Shared AI platform capabilities |
| `Meeting Intelligence:` | Transcript and meeting-memory workflows |
| `Knowledge Memory:` | Searchable operating knowledge |
| `AI Call Assistant:` | Call capture and transcription backends |
| `Hardening:` | Post-prototype reliability and security controls |
| `Spike:` | Time-bounded research with a decision deliverable |
| `License:` | Licensing, trademark, and asset-policy decisions |

Add labels when they improve filtering, automation, or ownership. Do not create
labels that merely duplicate the title prefix.

## Writing An Issue

A useful issue states:

1. the user, business, or operational problem;
2. the desired outcome;
3. current evidence or reproduction steps;
4. constraints and explicit non-goals;
5. acceptance criteria that can be verified;
6. security, privacy, data, deployment, and rollback concerns;
7. related or blocking issues.

Research issues should end in a recommendation, rejected alternatives, and
follow-up work. Broad architecture issues should be split before production
implementation when their decisions are still unsettled.

## Pull Requests

- Use one focused branch and pull request per issue.
- Start from an updated `main`.
- Do not mix unrelated cleanup or local artifacts into the branch.
- Include the issue reference, tests, assumptions, known gaps, operational
  impact, and rollback considerations.
- Keep infrastructure pull requests in draft until rendering, syntax, and
  relevant local smoke checks have passed.
- Do not merge and deploy as one unreviewed action. Production changes require
  separate human approval and validation.
- Identify AI-authored or substantially AI-assisted work in the pull request.

Repository-wide engineering and autonomous-agent expectations are also defined
in `.aiassistant/rules/`.

## Roadmap

The public planning model and current capability tracks are documented in
[`docs/roadmap.md`](docs/roadmap.md). The roadmap provides direction and
dependency context; individual GitHub issues remain the source for acceptance
criteria and implementation evidence.
