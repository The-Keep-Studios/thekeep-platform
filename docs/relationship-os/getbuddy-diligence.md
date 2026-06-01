# GetBuddy Diligence Checklist

GetBuddy is a candidate for Full Hearts rescue operations only. It should not be
treated as the Relationship OS and it should not automatically sync into Baserow.

Get written answers before putting sensitive rescue operations data in GetBuddy.

## Required Written Answers

| Topic | Required answer |
|---|---|
| Full export | Can Full Hearts export all records, notes, attachments, applications, application history, medical records, and user metadata on demand? |
| Export format | Are exports machine-readable, such as CSV, JSON, ZIP, or SQL dump? |
| Exit support | What is the process and timeline if Full Hearts leaves the service? |
| Deletion | Can Full Hearts request deletion from production systems, backups, analytics systems, and subprocessors? What timeline applies? |
| Data ownership | Does Full Hearts remain the controller or owner of organization-submitted data? |
| Advertising | Will adopter, foster, volunteer, donor, medical, or rescue-submitted data be used for targeted advertising, profiling, resale, or sponsored targeting? |
| AI/model training | Will rescue-submitted data or support conversations be used to train or improve AI systems? Is there an opt-out? |
| Subprocessors | What vendors process the data and where are they located? |
| Security | Is MFA available for admins? What roles exist? What audit logs are available? |
| Incident response | What notification timeline applies after a breach or suspected breach? |
| Attachments | Are uploaded files included in export and deletion workflows? |
| API access | Is API access available for export or reporting? Is it rate-limited? |
| Pricing | What parts are free, what may become paid, and what notice is given before pricing changes? |

## Decision Gate

Use GetBuddy for rescue operations only if the written answers are acceptable to
Full Hearts leadership.

If GetBuddy fails diligence, do not make Baserow a rescue-operations substitute.
Choose or build a separate rescue-ops system instead.

## Relationship OS Boundary

Even if GetBuddy is approved, Baserow receives only manually promoted strategic
records. No automatic sync, no ETL, no background copy job.
