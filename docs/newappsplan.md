Your instinct is mostly right.

Your colleague is **correct on MVP discipline**, but I think they’re slightly overcorrecting toward “simplest tool now” and underweighting “will this still be the right data shape in six months?”

## My read

### 1. “Baserow over Corteza” is reasonable, not obviously correct

Baserow is attractive because it’s fast to stand up, table-shaped, form-friendly, API-first, and easy for humans to understand. Its docs show forms, Kanban/calendar-style views, API docs, table-level tokens, webhooks, permissions, snapshots, and audit-log concepts. That’s plenty for an MVP relationship board. ([Baserow][1])

But Corteza is not being disqualified by hardware. Corteza’s own requirement table says 1–500 users is **1 vCPU / 2 GB RAM**, with PostgreSQL recommended. That is trivial on a maxed Framework Desktop. ([docs.cortezaproject.org][2])

The real question is **configuration labor**, not resource footprint.

So I’d reframe it:

> Baserow is better for “start using this tomorrow.”
> Corteza is better for “build a governed relationship application.”

Given your actual need is “executive who’s-who system,” Baserow might be enough. Given your TKS consulting/portfolio goal, Corteza is still strategically interesting.

### 2. They are dead right on “humans as the API”

Strong agree. No sync workers yet.

Manual elevation is the right MVP rule:

> GetBuddy contains rescue ops.
> Relationship OS contains only strategic contacts someone intentionally promotes.

No ETL. No silent sync. No background job that quietly copies sensitive rescue data into a quasi-business system.

### 3. Flat permissions are fine, but only if the data is intentionally boring

I agree with flattening permissions **for the first version**, but I would not remove the governance fields.

Do not build complex RBAC yet. But keep fields like:

```text
Owning Entity: TKS / Full Hearts / Shared
Contact Purpose: Business / Rescue / Donor / Creative / Vendor / Personal
Consent Notes:
Sensitive? Yes/No
Do Not Use For:
```

That gives you future-proofing without building a permissions cathedral.

### 4. Their GetBuddy advice is a little too trusting

GetBuddy’s pitch is genuinely compelling: free, role-based access, application routing, white-glove migration, and “no hidden fees.” ([GetBuddy][3])

But I would **not** “accept the privacy trade-offs for now” without one written answer: can Full Hearts export all records, notes, attachments, and application history if leaving?

Also, GetBuddy’s privacy policy has language around targeted advertising and sharing practices that may qualify as a “sale” under some state privacy laws. That doesn’t prove misuse, but it means “free forever” needs written clarification before you hand them sensitive adopter/foster/volunteer data. ([GetBuddy][4])

### 5. CiviCRM still probably isn’t the MVP answer

CiviCRM is absolutely worth respecting. It owns nonprofit CRM territory: contributions, memberships, accounting export, case management, events, email marketing, peer-to-peer fundraising, reports, and CMS integration. ([civicrm.org][5])

But its own docs call it “a demanding web application,” with PHP/MySQL/MariaDB requirements, and PostgreSQL is not compatible. ([docs.civicrm.org][6])

On your hardware, it would run. The issue is **wrong shape and maintenance gravity**. It’s more useful if Full Hearts becomes donor/event/fundraising heavy. It is not the best tool for a cross-org executive relationship map.

## My recommendation

Do this:

### Phase 1: Baserow MVP

Use Baserow for the **Relationship OS prototype** because your colleague is right about speed-to-value.

Tables:

```text
People
Organizations
Roles / Affiliations
Touchpoints
Opportunities / Strategic Moves
Contractors & Creatives
Entity Boundary / Consent Notes
```

Keep it manual. No sync.

### Phase 2: GetBuddy evaluation

Use GetBuddy only if they pass:

```text
Full export?
Attachments included?
Notes included?
Application history included?
Data deletion on exit?
No rescue-submitted contact data used for sponsored targeting?
```

### Phase 3: Re-evaluate Corteza after actual use

After 30–60 days, ask:

* Are we fighting Baserow’s limits?
* Do we need real workflows?
* Do we need stronger permissions?
* Do we want this as a public TKS case study?
* Do we want reusable “Relationship OS for small mission orgs” consulting collateral?

If yes, migrate the proven schema to Corteza.

## Blunt call

Your colleague is right that the **first implementation should be simpler**.

You are right that **hardware is not the constraint**.

The compromise is:

> **Start with Baserow, but design the schema like it may graduate to Corteza.**

That avoids yak-shaving while preserving the bigger TKS software/consulting story.

[1]: https://baserow.io/user-docs/database-api "Baserow Database API documentation"
[2]: https://docs.cortezaproject.org/corteza-docs/2024.9/devops-guide/system-requirements.html "System Requirements :: Corteza Docs"
[3]: https://www.getbuddy.com/animal-shelter-rescue-software "Buddy Pro - Free Shelter Management Software for Rescues and Shelters"
[4]: https://www.getbuddy.com/privacy-policy "Privacy Policy | GetBuddy"
[5]: https://civicrm.org/explore-civicrm "What is CiviCRM | CiviCRM"
[6]: https://docs.civicrm.org/installation/en/latest/requirements/ "Requirements - CiviCRM Installation Guide - CiviCRM Documentation"
