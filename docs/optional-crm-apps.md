# Optional CRM Apps

Baserow remains the core relationship-management app for now. Twenty and
EspoCRM stay in the repo as optional apps that can be tested locally or enabled
explicitly through GitOps.

Use fake or low-risk sample data while comparing the CRMs. Do not import rescue,
medical, adoption, private convention, or client data until an app has been
deliberately chosen for that data class.

## Local Test

Run one candidate at a time:

```bash
scripts/dev-smoke.sh twenty
scripts/dev-observe.sh twenty
```

```bash
scripts/dev-smoke.sh espocrm
scripts/dev-observe.sh espocrm
```

Run both candidates when the workstation has enough disk and memory:

```bash
scripts/dev-smoke.sh optional-crm
scripts/dev-observe.sh optional-crm
```

The old `crm-bakeoff` target remains as a compatibility alias for local
comparison:

```bash
scripts/dev-smoke.sh crm-bakeoff
scripts/dev-observe.sh crm-bakeoff
```

Default local URLs:

```text
Twenty:  http://localhost:18083
EspoCRM: http://localhost:18084
```

The smoke scripts create deterministic dev-only Kubernetes secrets in each app
namespace. Override them only when also deleting the disposable cluster or PVCs.

## GitOps Enablement

Both apps are disabled by default:

```yaml
platform_optional_apps:
  twenty:
    enabled: false
  espocrm:
    enabled: false
```

Enable either app, or both, in `ansible/production_vars.yml`:

```yaml
platform_optional_apps:
  twenty:
    enabled: true
  espocrm:
    enabled: false
```

Add only the secrets required by the enabled app.

EspoCRM can optionally manage `emailServerAllowedAddressList` from
`ansible/production_vars.yml`. The built-in `gmail` profile expands to the
exact Gmail and Google Workspace mail endpoints:

```yaml
platform_optional_apps:
  espocrm:
    enabled: true
    email_server_allowlist_profile: gmail
```

The profile allows only:

```text
imap.gmail.com:993
smtp.gmail.com:587
smtp.gmail.com:465
```

For another provider, use a custom list of exact `host:port` pairs. Wildcards
are rejected.

```yaml
platform_optional_apps:
  espocrm:
    enabled: true
    email_server_allowed_address_list:
      - "imap.example.com:993"
      - "smtp.example.com:587"
```

Set either `email_server_allowlist_profile` or
`email_server_allowed_address_list`, not both. Omit both values to leave the
EspoCRM setting unmanaged. Set `email_server_allowed_address_list: []` to
explicitly clear an allowlist previously managed through this playbook.

For an already-running EspoCRM deployment, apply only the email configuration
without running the full platform setup:

```bash
ansible-playbook -K \
  -i ansible/inventory.production.ini \
  ansible/configure_espocrm_email.yml
```

The focused playbook applies the merged EspoCRM manifests, updates the runtime
configuration, restarts the web and daemon deployments when needed, verifies
the effective EspoCRM setting, and tests connectivity to every configured
endpoint. For a one-time profile selection that is not stored in
`production_vars.yml`, pass `-e espocrm_email_config_profile=gmail`.

Twenty:

```yaml
platform_secrets:
  twenty_pg_database_password: "CHANGE_ME"
  twenty_encryption_key: "CHANGE_ME"
  twenty_app_secret: "CHANGE_ME"
```

EspoCRM:

```yaml
platform_secrets:
  espocrm_db_root_password: "CHANGE_ME"
  espocrm_db_password: "CHANGE_ME"
  espocrm_admin_password: "CHANGE_ME"
```

### EspoCRM Assistant

The EspoCRM assistant is disabled by default and requires EspoCRM itself to be
enabled. Turning on `platform_optional_apps.espocrm_assistant.enabled` does not
turn on `platform_optional_apps.espocrm.enabled`; the production playbook fails
early if the assistant is enabled without EspoCRM.

When enabled, the assistant runs in the `espocrm` namespace as an internal
Kubernetes service. It exposes a streamable HTTP MCP endpoint at `/mcp` for the
future OAuth-capable MCP gateway, and a separate approval service on port
`8090`. Neither endpoint should be internet-exposed directly.

Required GitOps settings:

```yaml
platform_optional_apps:
  espocrm:
    enabled: true
  espocrm_assistant:
    enabled: true
```

Required assistant secrets:

```yaml
platform_secrets:
  espocrm_assistant_read_api_key: "CHANGE_ME"
  espocrm_assistant_read_secret_key: ""
  espocrm_assistant_write_api_key: "CHANGE_ME"
  espocrm_assistant_write_secret_key: ""
  espocrm_assistant_token: "CHANGE_ME"
  espocrm_assistant_apply_token: "CHANGE_ME"
```

Use separate EspoCRM API users for read and write access. The read API user is
used by assistant-visible MCP tools. The write API user is used only by the
human-approved apply endpoint. The `*_secret_key` values are optional HMAC
secrets if HMAC is enabled for the corresponding EspoCRM API user. The
assistant token protects internal non-mutating JSON helper routes. The apply
token protects `/approval/apply-change` and should be shared only with the
approved executor path.

The assistant source, tests, Dockerfile, release workflow, and service-specific
developer documentation live in the dedicated service repository:
`https://github.com/The-Keep-Studios/espocrm-assistant`.

TKP consumes the published service image by immutable digest:

```text
ghcr.io/the-keep-studios/espocrm-assistant@sha256:aea7326a6df729feb94595740040aba184274d0f897fdd4ffcc5d8408df3e585
```

That digest was resolved from public tag `sha-7235661`, built from service
commit `72356613fccb406af4d7511e45af68cb7acedf0f`. Future assistant service
releases should update only the digest and any changed operator contract in TKP.
Do not reintroduce the service source, tests, package metadata, Dockerfile, or
service release workflow into this repository.

For local service commands, streamable HTTP configuration, approval endpoint
examples, and the build-vs-wrap MCP evaluation, see the service repository.

If external HTTPS validation is enabled, include the enabled public CRM host in
`direct_http_urls` so the direct-origin exposure check covers it too. The
EspoCRM assistant has no public hostname and should not be added here.

```yaml
direct_http_urls:
  - "http://twenty.thekeepstudios.com"
```

or:

```yaml
direct_http_urls:
  - "http://espocrm.thekeepstudios.com"
```

## Hostnames

The optional app manifests use these external hosts:

```text
Twenty:  https://twenty.thekeepstudios.com
EspoCRM: https://espocrm.thekeepstudios.com
```

Wire only enabled hosts through Cloudflare Tunnel.

## Backups

Each optional app includes its own backup CronJob:

```text
Twenty:  twenty/twenty-backup
EspoCRM: espocrm/espocrm-backup
```

The backup jobs write compressed database dumps and app-local data archives to
app-specific backup PVCs. Validate backups manually before putting real business
data into either CRM.

Manual backup examples:

```bash
kubectl create job -n twenty twenty-backup-manual-$(date +%s) \
  --from=cronjob/twenty-backup
```

```bash
kubectl create job -n espocrm espocrm-backup-manual-$(date +%s) \
  --from=cronjob/espocrm-backup
```

## Cleanup

Local cleanup:

```bash
kubectl delete namespace twenty
kubectl delete namespace espocrm
```

Disposable-cluster cleanup:

```bash
scripts/dev-cluster-down.sh
```

Trial cleanup:

1. Set the app's `platform_optional_apps.<app>.enabled` value to `false`.
2. Re-render/apply GitOps.
3. Confirm the selected Argo CD app disappears or is pruned intentionally.
4. Delete app PVCs only after deciding no trial data needs to be kept.
