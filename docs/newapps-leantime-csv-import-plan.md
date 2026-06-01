# New Apps Leantime PM Import Plan

This document plans how to turn `docs/newappsplan.md` into Leantime project-management records without losing sight of the actual goal: start capturing and organizing strategic relationship work from conventions, events, and partner conversations.

The source strategy lives in `docs/newappsplan.md`. This document is only an optional project-management import helper.

## Source Plan

Input document:

- `docs/newappsplan.md`

The plan is about selecting and sequencing new application work around:

- Relationship OS MVP, likely starting with Baserow.
- Manual data boundaries between GetBuddy rescue operations and the Relationship OS.
- Governance fields for future portability and permissions.
- GetBuddy evaluation before committing sensitive rescue data.
- Corteza re-evaluation after real usage proves whether Baserow is too limited.
- CiviCRM as a later nonprofit CRM option, not the immediate MVP.

## Leantime Import Path

Use a manual or CSV-backed import path first.

Do not block the Relationship OS planning work on Leantime MCP automation.

Reasoning:

- The strategic app plan is the important artifact.
- The immediate business need is to record useful relationship context from real events and conversations.
- Leantime import automation is helpful only if it saves time without creating a separate integration project.
- The MCP setup/debugging path has already exceeded the value of automating this one planning import.

Leantime's CSV importer supports common objects including To-Dos, Milestones, Users, Projects, Ideas, and Goals. The official support article points to import templates for each supported object type:

- <https://support.leantime.io/en/article/importing-data-via-csv-1v941gy/>

Generated CSV or JSON staging artifacts should live outside normal Git history:

```text
.artifacts/leantime-import/newapps/
```

That keeps the repository focused on durable infrastructure and planning while still giving PMs reviewable import files.

## MCP Decision

MCP is deferred for this workflow.

Decision recorded on 2026-05-31:

- Leantime MCP server-side discovery worked and reported tools.
- Local MCP bridge/client behavior was not reliable enough to justify continued setup during this planning task.
- The effort was becoming a project-management automation rabbit hole instead of helping capture the actual relationship strategy.
- The MCP plugin can be revisited later as a separate infrastructure/PM operations task.

Do not remove the strategic plan because MCP was not ready. The failed automation attempt does not invalidate the Baserow/GetBuddy/Corteza planning work.

## Proposed Leantime Shape

Create one Leantime project:

```text
Project: New Apps Evaluation and Relationship OS MVP
```

Purpose:

```text
Evaluate and sequence the next application layer for TKS and Full Hearts, starting with a Relationship OS MVP while preserving data boundaries, exportability, and future migration paths.
```

## Record Creation Order

Create records in this order:

1. Project
2. Goals
3. Milestones
4. Ideas
5. To-dos

Users are omitted for now unless the importing PM wants assignees created or updated in the same pass.

Before creating final CSVs, confirm the exact fields Leantime expects from the current import templates.

## CSV Files To Prepare

1. `01-projects.csv`
2. `02-goals.csv`
3. `03-milestones.csv`
4. `04-ideas.csv`
5. `05-todos.csv`

Before generating final CSVs, download the current Leantime templates from the import UI or the official linked template sheet, then map these planned fields to the exact headers Leantime expects.

## Project CSV

Target record:

```text
Name: New Apps Evaluation and Relationship OS MVP
Client / Organization: The Keep Studios
Status: Active
Description: Evaluate Baserow, GetBuddy, Corteza, and related governance decisions for the next app layer.
```

If Leantime requires a client/company field and no matching client exists, create or select:

```text
The Keep Studios
```

## Goals CSV

Proposed goals:

| Goal | Outcome |
| --- | --- |
| Launch Relationship OS MVP | Baserow is either accepted as MVP or rejected with clear reasons. |
| Preserve Data Boundaries | Rescue operations data is not silently copied into business relationship tooling. |
| Validate GetBuddy Exit Safety | Full Hearts understands export, deletion, attachment, notes, and privacy constraints before relying on GetBuddy. |
| Define Graduation Criteria | The team knows when to stay on Baserow, migrate to Corteza, or defer both. |
| Keep Future Handoff Easy | Schema, governance fields, and decisions are documented enough for another operator or consultant to understand. |

## Milestones CSV

Proposed milestones:

| Milestone | Purpose | Suggested Status |
| --- | --- | --- |
| Import Setup and Template Validation | Confirm Leantime CSV headers, import order, and project shell. | Ready |
| Relationship OS MVP Design | Define Baserow tables, governance fields, and manual promotion workflow. | Ready |
| Baserow MVP Implementation | Stand up and validate the first usable Relationship OS prototype. | Planned |
| GetBuddy Evaluation | Answer export, deletion, privacy, and rescue-data questions before operational reliance. | Planned |
| Corteza Re-Evaluation | Decide whether actual usage justifies graduating beyond Baserow. | Planned |
| Decision and Next Build Plan | Convert evaluation results into a concrete implementation path. | Planned |

## Ideas CSV

Import as Ideas if Leantime is being used to preserve strategic alternatives separately from actionable work.

| Idea | Notes |
| --- | --- |
| Start with Baserow, design for possible Corteza migration | Fast MVP without throwing away future data-shape thinking. |
| Keep humans as the API between GetBuddy and Relationship OS | Prevent silent copying of sensitive rescue data. |
| Preserve governance fields without complex RBAC | Keep future permissions possible without building a permissions system now. |
| Require written GetBuddy export answers | Do not put sensitive rescue data into a tool without exit clarity. |
| Revisit Corteza after 30 to 60 days | Let real usage decide whether Baserow limits matter. |
| Defer CiviCRM | Useful later for donor/event/fundraising gravity, not for this MVP. |

## To-Dos CSV

Proposed import rows. Exact status, priority, estimate, and milestone fields should be mapped to the current Leantime template.

| Milestone | To-Do | Description | Priority |
| --- | --- | --- | --- |
| Import Setup and Template Validation | Download current Leantime CSV templates | Get official templates for Projects, Goals, Milestones, Ideas, and To-Dos before generating final CSVs. | High |
| Import Setup and Template Validation | Confirm import order in a small test | Import one project, one milestone, and one to-do before bulk import. | High |
| Import Setup and Template Validation | Decide whether assignees are needed | If yes, prepare Users CSV or map tasks to existing Leantime users. | Medium |
| Relationship OS MVP Design | Define People table | Include identity, organization links, purpose, consent notes, sensitive flag, and do-not-use-for fields. | High |
| Relationship OS MVP Design | Define Organizations table | Include org type, owning entity, relationship status, strategic relevance, and notes. | High |
| Relationship OS MVP Design | Define Roles and Affiliations table | Model many-to-many people-to-organization roles without flattening important context. | High |
| Relationship OS MVP Design | Define Touchpoints table | Capture intentional interactions, dates, owners, outcomes, and next actions. | Medium |
| Relationship OS MVP Design | Define Opportunities and Strategic Moves table | Track introductions, partnerships, donor moves, contractor opportunities, and follow-up state. | Medium |
| Relationship OS MVP Design | Define Contractors and Creatives table | Separate vendor/creative pipeline data from general contacts where useful. | Medium |
| Relationship OS MVP Design | Define Entity Boundary and Consent Notes fields | Preserve TKS / Full Hearts / Shared ownership, consent notes, sensitive flag, and do-not-use-for context. | High |
| Relationship OS MVP Design | Define manual promotion rule from GetBuddy | Document that GetBuddy data enters Relationship OS only by intentional human promotion. | High |
| Baserow MVP Implementation | Stand up Baserow workspace | Create the Relationship OS prototype workspace and initial tables. | High |
| Baserow MVP Implementation | Configure forms and views | Create useful entry forms, Kanban/calendar-style views if available, and simple operator views. | Medium |
| Baserow MVP Implementation | Add sample records | Use non-sensitive sample data to validate the schema and workflows. | High |
| Baserow MVP Implementation | Validate export path | Confirm CSV/API export is usable for the MVP data shape. | High |
| Baserow MVP Implementation | Write MVP operating notes | Document how contacts are added, promoted, reviewed, and cleaned up. | Medium |
| GetBuddy Evaluation | Ask GetBuddy export questions | Confirm full export, attachments, notes, application history, deletion on exit, and privacy/targeting constraints. | High |
| GetBuddy Evaluation | Record GetBuddy answers in Leantime | Attach or summarize written answers in the project. | High |
| GetBuddy Evaluation | Decide acceptable rescue-data usage | Decide what data may live in GetBuddy and what must stay out. | High |
| Corteza Re-Evaluation | Define 30 to 60 day review criteria | List Baserow pain signals: workflows, permissions, reporting, API limits, and consulting/case-study value. | Medium |
| Corteza Re-Evaluation | Re-check Corteza implementation cost | Estimate configuration labor, hosting, security, and handoff complexity after MVP usage. | Medium |
| Corteza Re-Evaluation | Make stay/migrate/defer decision | Decide whether to stay on Baserow, migrate to Corteza, or defer the decision. | High |
| Decision and Next Build Plan | Write final recommendation | Summarize chosen app path, rationale, risks, and next build steps. | High |
| Decision and Next Build Plan | Convert accepted path into implementation backlog | Create follow-up Leantime tasks or a new project for the chosen app. | High |

## Import Procedure

1. Download fresh Leantime CSV templates.
2. Generate draft CSVs under `.artifacts/leantime-import/newapps/`.
3. Open the CSVs in a spreadsheet editor and review names, descriptions, statuses, priorities, and milestone mappings.
4. Import `01-projects.csv`.
5. Import `02-goals.csv`.
6. Import `03-milestones.csv`.
7. Import `04-ideas.csv`.
8. Import `05-todos.csv`.
9. Spot-check in Leantime:
   - Project exists.
   - Milestones are attached to the right project.
   - To-dos are attached to the right milestone.
   - Ideas and goals are readable and not duplicative.
10. Export or screenshot the resulting project as evidence.

## MCP Follow-Up Criteria

Revisit MCP only as a separate task, not as a blocker for relationship planning.

Pick MCP back up only if:

- Token creation, rotation, and revocation are documented.
- The MCP client configuration is documented without committing secrets.
- Read/write scopes are understood.
- We have a repeatable dry-run or staging-review workflow before writes.
- We know how to audit what the agent changed in Leantime.
- The expected time savings are larger than the setup and maintenance burden.

If MCP becomes a normal workflow, document it as infrastructure and PM operations work, not as an ad-hoc shortcut.
