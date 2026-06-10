# Leantime UI and MCP Routing

## Contract

The public Leantime host has two distinct responsibilities:

- `https://projects.thekeepstudios.com/dashboard/home` and other normal paths serve the Leantime UI.
- `https://projects.thekeepstudios.com/mcp` serves the MCP streamable HTTP transport.

An exact request to `/` is handled by Traefik and redirected to `/dashboard/home`.
This prevents an enabled plugin from replacing Leantime's authenticated default
route. The general prefix Ingress still sends `/mcp` and all other application
paths to the Leantime service.

Leantime's core front controller defines `dashboard.home` as the default route.
Official Leantime MCP documentation says the plugin endpoint is `/mcp`.

## Why the Guard Exists

Issue #26 observed that an authenticated browser request to `/` returned the MCP
transport error:

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Not Acceptable: Client must accept text/event-stream for GET requests."
  }
}
```

Anonymous requests did not reproduce the failure because Leantime redirected
them to `/auth/login` first. The regression therefore needs an authenticated
browser session to reproduce at the application layer. The exact-root Traefik
redirect avoids that route collision before the request reaches Leantime.

## Validation

Run the anonymous route checks:

```bash
scripts/check-leantime-routing.sh
```

To exercise the original authenticated-browser failure, provide the complete
Leantime `Cookie` header value without committing it:

```bash
LEANTIME_BROWSER_COOKIE='leantime_session=REDACTED' \
  scripts/check-leantime-routing.sh
```

To verify the authenticated MCP stream as well:

```bash
LEANTIME_BROWSER_COOKIE='leantime_session=REDACTED' \
LEANTIME_MCP_TOKEN='REDACTED' \
  scripts/check-leantime-routing.sh
```

The script verifies:

- browser and `text/event-stream` requests to `/` redirect to `/dashboard/home`;
- the dashboard path returns HTML, never an MCP JSON-RPC response;
- unauthenticated `/mcp` requests are rejected;
- when a token is supplied, `/mcp` responds as an authenticated SSE transport.

## Security Boundary

- Keep MCP traffic on the dedicated `/mcp` path. Do not expose it at `/`.
- Require a personal access token or scoped API credential for every MCP client.
- Never commit MCP tokens, browser cookies, or session IDs.
- Use HTTPS only and retain Cloudflare/Traefik request limits and logging.
- Validate the `Origin` header where the plugin supports it. Restrict accepted
  origins to the Leantime host or known MCP clients instead of using a wildcard.
- Treat MCP as a privileged automation interface: it can read and mutate project
  data with the permissions of its token.
- For broader or external access, move MCP behind Cloudflare Access or an
  internal-only hostname and apply IP allowlisting. The current same-host path is
  acceptable only for the directly controlled confidential deployment.
- Rotate tokens after suspected exposure and review Leantime/Loki logs for
  unexpected tool calls or repeated authentication failures.

## Upstream Status

The platform workaround is intentionally independent of plugin internals. The
reported behavior conflicts with both Leantime's core default route and the
documented `/mcp` endpoint, so the MCP Server plugin remains the likely upstream
source. Capture the plugin version, authenticated request evidence, and route
registration details before filing an upstream Leantime issue.
