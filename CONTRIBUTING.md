# Contributing

Keep changes focused, reviewable, and free of confidential data.

## Where Work Belongs

- **GitHub:** public roadmap, architecture, code, bugs, docs, and integrations.
- **Leantime:** private execution, workload, and client-specific tasks.
- **EspoCRM:** active job, sales, client, and publishing opportunities.
- **Baserow:** relationship and organization memory.
- **Gmail:** communication source, not a system of record.

Never publish credentials, private CRM/contact/job-search data, client details,
database exports, or undisclosed vulnerabilities. Follow `SECURITY.md`.

## Issue Titles

Use a stable prefix such as:

`Bug:`, `Security:`, `Architecture:`, `Roadmap:`, `Installability:`,
`Demo Mode:`, `Integrations:`, `AI Services:`, `Meeting Intelligence:`,
`Knowledge Memory:`, `AI Call Assistant:`, `Hardening:`, `Spike:`, or
`License:`.

Labels should add filtering or ownership value, not duplicate the title.

## Good Issues

State:

1. the problem and desired outcome;
2. evidence or reproduction;
3. constraints and non-goals;
4. verifiable acceptance criteria;
5. security, data, deployment, and rollback concerns;
6. dependencies.

Research issues should end in a recommendation, not an implied implementation.

## Pull Requests

- Use one issue, branch, and PR per concern.
- Start from updated `main`.
- Stage only intentional files.
- Include tests, assumptions, gaps, operational impact, and rollback.
- Keep infrastructure PRs draft until relevant static/smoke checks pass.
- Merge and deploy as separate human-approved actions.
- Identify substantially AI-authored work.

See `docs/roadmap.md` for public planning and `.aiassistant/rules/` for
repository working rules.
