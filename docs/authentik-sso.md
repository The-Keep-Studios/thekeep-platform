# Authentik SSO Runbook

Authentik is the platform identity hub. Use native OIDC for apps that support it
well, and use Authentik Proxy Provider forward-auth for apps that need an
external auth gate.

## Current Pattern

The Authentik deployment includes:

- `identity/authentik-forward-auth`: Traefik `Middleware` for Authentik
  forward-auth.
- `identity/authentik-forward-auth-outpost-routes`: an Ingress that routes
  `/outpost.goauthentik.io/*` on protected app hosts back to Authentik's
  embedded outpost.

The middleware is intentionally not attached to app ingresses by default. Attach
it only after the Authentik Proxy Provider exists and the outpost route has been
validated.

## Authentik Setup

In Authentik admin:

1. Confirm `authentik Embedded Outpost` has `authentik_host` set to
   `https://auth.thekeepstudios.com`.
2. Create a Proxy Provider for platform forward-auth.
3. Use Forward auth mode. Domain-level mode is the fastest internal-tools gate;
   single-application mode gives better per-app access control.
4. Create or attach an Authentik Application for the provider.
5. Assign the provider to `authentik Embedded Outpost`.

After saving, test an outpost route:

```bash
curl -I https://baserow.thekeepstudios.com/outpost.goauthentik.io/ping
curl -I https://crm.thekeepstudios.com/outpost.goauthentik.io/ping
```

A healthy route returns `204` or an Authentik-managed response, not a Traefik
`404` and not the upstream application.

## Enable Forward Auth

Apply the middleware annotation to each app ingress once the provider is ready:

```bash
kubectl annotate ingress baserow-ingress -n baserow \
  traefik.ingress.kubernetes.io/router.middlewares=identity-authentik-forward-auth@kubernetescrd \
  --overwrite

kubectl annotate ingress espocrm-ingress -n espocrm \
  traefik.ingress.kubernetes.io/router.middlewares=identity-authentik-forward-auth@kubernetescrd \
  --overwrite

kubectl annotate ingress wisemapping-ingress -n wisemapping \
  traefik.ingress.kubernetes.io/router.middlewares=identity-authentik-forward-auth@kubernetescrd \
  --overwrite

kubectl annotate ingress leantime-ingress -n default \
  traefik.ingress.kubernetes.io/router.middlewares=identity-authentik-forward-auth@kubernetescrd \
  --overwrite

kubectl annotate ingress argocd-server-ingress -n argocd \
  traefik.ingress.kubernetes.io/router.middlewares=identity-authentik-forward-auth@kubernetescrd \
  --overwrite
```

For monitoring, replace the current BasicAuth middleware in
`kubernetes/platform/monitoring/kube-prometheus-stack.values.yaml` with:

```yaml
traefik.ingress.kubernetes.io/router.middlewares: identity-authentik-forward-auth@kubernetescrd
```

If an ingress already has a middleware that must remain, chain both values with a
comma in Traefik annotation order:

```yaml
traefik.ingress.kubernetes.io/router.middlewares: identity-authentik-forward-auth@kubernetescrd,namespace-other-middleware@kubernetescrd
```

## Native OIDC Follow-Up

Native app SSO is preferable when the app handles authorization cleanly:

- Leantime reads OIDC settings from `platform_oidc.leantime` and the
  `leantime-oidc` secret.
- WiseMapping has an `oidc` Spring profile but needs Authentik client values in
  `platform_oidc.wisemapping`.
- Argo CD, Grafana, and GitLab should move from proxy-only gates to native OIDC
  once provider automation is in place.

Keep Baserow and EspoCRM behind forward-auth unless a supported native OIDC
configuration is deliberately added and tested.
