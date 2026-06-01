# Data Boundary Policy

The Relationship OS exists to track strategic relationships. It is not a rescue
operations system and it is not a data lake.

## Core Rule

Humans are the API.

Records may be entered or promoted into the Relationship OS only when a person
intentionally decides the contact belongs in the strategic relationship layer.
There is no automatic sync from GetBuddy, email, forms, spreadsheets, or other
systems.


## Allowed Data

Allowed:

- strategic contact information
- affiliation and role context
- relationship notes
- follow-up dates
- opportunity context
- consent and boundary notes
- high-level donor, partner, vendor, creative, or rescue-alliance context

## Disallowed Data

Do not store routine rescue operations data here:

- animal medical records
- adoption applications
- foster screening data
- volunteer screening data
- adopter household details
- animal intake histories
- sensitive medical or behavioral notes about animals
- donor receipt or tax substantiation records
- private legal, employment, or HR records

If this data is needed, keep it in the proper operations system or legal/accounting
system.

## Entity Boundary

TKS and Full Hearts are connected, but they are not the same legal entity.

Every strategic record should answer:

- Which entity owns this relationship?
- Why is it appropriate to store this contact here?
- What should this contact not be used for?
- Is the record sensitive?

Use these fields:

- `Owning Entity`
- `Contact Purpose`
- `Sensitive`
- `Consent Notes`
- `Do Not Use For`

## Workspace Boundary

Use two workspaces:

- `TKS Relationship OS`
- `Full Hearts Strategic Relationships`

Do not assume workspace separation is a legal or technical air gap. Baserow
instance admins can still administer the whole installation. Workspace separation
is a practical operating boundary for small-team use.

## Promotion Rule

A record may move from rescue operations into the strategic workspace only when:

1. It has a clear strategic purpose.
2. The relationship owner can explain why it belongs there.
3. The record excludes operationally sensitive details.
4. Any restrictions are captured in `Consent Notes` and `Do Not Use For`.

## Future Automation Rule

Before adding automation, write a short design note that answers:

- What data moves?
- Who approved the movement?
- What is the rollback path?
- What logs prove the movement happened?
- What privacy boundary could the automation violate?

Until that note exists, keep the system manual.
