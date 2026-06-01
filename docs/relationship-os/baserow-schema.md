# Baserow Schema

Create two Baserow workspaces with the same starter schema:

- `TKS Relationship OS`
- `Full Hearts Strategic Relationships`

Keep the schemas similar at first so the operating rhythm is shared, but keep
the workspaces separate so TKS and Full Hearts data do not blur by default.

## Tables

### People

Purpose: individual humans worth remembering, following up with, influencing,
helping, hiring, partnering with, or asking for support.

Fields:

| Field | Type | Notes |
|---|---|---|
| Full Name | Single line text | Required |
| Preferred Name | Single line text | Optional |
| Primary Email | Email | Leave blank if not appropriate to store |
| Primary Phone | Phone number | Leave blank if not appropriate to store |
| Location | Single line text | City, region, or convention context |
| Relationship Owner | Collaborator or single select | Who owns follow-up |
| Warmth | Single select | Cold, New, Warm, Active, Dormant |
| Contact Purpose | Single select | Business, Rescue, Donor, Creative, Vendor, Personal |
| Owning Entity | Single select | TKS, Full Hearts, Shared |
| Sensitive | Boolean | Use for extra caution, not for fine-grained RBAC |
| Do Not Use For | Long text | Explicit restrictions |
| Consent Notes | Long text | Where permission/context came from |
| Last Touchpoint At | Date | Update from touchpoint log |
| Next Follow-Up At | Date | Drives calendar view |
| Tags | Multiple select | Keep short |
| Notes | Long text | Relationship context |

Recommended views:

- `All People`
- `Needs Follow-Up`
- `Warm Relationships`
- `New Leads`
- `Sensitive Review`

### Organizations

Purpose: companies, rescues, funders, stores, vendors, studios, press outlets,
clinics, agencies, and institutions.

Fields:

| Field | Type | Notes |
|---|---|---|
| Organization Name | Single line text | Required |
| Organization Type | Single select | Publisher, Studio, Rescue, Funder, Vendor, Venue, Press, Clinic, Government, Other |
| Website | URL | Optional |
| Location | Single line text | HQ or relevant local market |
| Strategic Value | Single select | Low, Medium, High, Critical |
| Status | Single select | New, Active, Watching, Dormant, Blocked |
| Primary Contact | Link to People | Optional |
| Owning Entity | Single select | TKS, Full Hearts, Shared |
| Notes | Long text | Why this org matters |

Recommended views:

- `Priority Organizations`
- `Publishing Ecosystem`
- `Rescue Ecosystem`
- `Local Rochester`
- `Vendors`

### Roles / Affiliations

Purpose: join people to organizations over time. This should be a real table
instead of a text note because people move roles and organizations.

Fields:

| Field | Type | Notes |
|---|---|---|
| Person | Link to People | Required |
| Organization | Link to Organizations | Required |
| Title / Role | Single line text | Optional |
| Department / Team | Single line text | Optional |
| Current | Boolean | True for current affiliation |
| Start Date | Date | Optional |
| End Date | Date | Optional |
| Influence Score | Number | 1 to 5, subjective |
| Notes | Long text | Context and caveats |

Recommended views:

- `Current Roles`
- `Former Roles`
- `High Influence`

### Touchpoints

Purpose: narrative log of interactions. This is the memory layer.

Fields:

| Field | Type | Notes |
|---|---|---|
| Touched At | Date and time | Required |
| Touchpoint Type | Single select | Meeting, Email, Call, Convention, Social, Intro, Donation, Volunteer, Other |
| People | Link to People | Optional but preferred |
| Organizations | Link to Organizations | Optional |
| Summary | Single line text | Short, scannable |
| Detailed Notes | Long text | Actual context |
| Follow-Up Required | Boolean | Drives follow-up view |
| Follow-Up At | Date | Optional |
| Owner | Collaborator or single select | Responsible person |
| Confidentiality | Single select | Normal, Internal, Sensitive |
| Related Opportunities | Link to Opportunities | Optional |

Recommended views:

- `Logbook`
- `Follow-Up Due`
- `This Month`
- `By Owner`

### Opportunities

Purpose: a concrete strategic move or possible move. If it turns into delivery
work, move execution into a real project-management tool.

Fields:

| Field | Type | Notes |
|---|---|---|
| Title | Single line text | Required |
| Opportunity Type | Single select | Publishing, Consulting, Fundraising, Partnership, Event, Vendor, Press, Rescue Alliance, Other |
| People | Link to People | Optional |
| Organizations | Link to Organizations | Optional |
| Stage | Single select | Idea, Qualifying, Active, Waiting, Won, Lost, Parked |
| Estimated Value | Number | Optional dollars |
| Nonfinancial Value | Single select | Low, Medium, High, Critical |
| Owner | Collaborator or single select | Responsible person |
| Target Date | Date | Drives calendar view |
| Next Step | Long text | One concrete action |
| Risk Notes | Long text | Risks, conflicts, sensitivities |

Recommended views:

- `Kanban by Stage`
- `Calendar by Target Date`
- `High Value`
- `Waiting on Others`

## Launch Rule

Start with these tables and views only. Do not add automation until there is at
least one month of real use and a clear repeated pain point.
