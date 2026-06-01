# Optional CRM Apps

Twenty and EspoCRM are optional platform applications. They are kept in the
repository so they can be trialed or enabled later without making either CRM a
core platform dependency.

Baserow remains the core relationship-management app for now.

Rules for optional CRM apps:

- Disabled by default in GitOps.
- Enabled explicitly through Ansible variables.
- Deployed in their own namespaces, `twenty` and `espocrm`.
- Backed up by app-specific CronJobs before any shared or production trial.
- No rescue, medical, adoption, private convention, or client data should be
  imported until a CRM has been deliberately chosen for that data class.
