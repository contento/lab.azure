# Code Review: Typecast (static-web-app-ascii)

Reviewed: 2026-09-06
Scope: `app/`, `api/`, `infra/`, and project docs. `npm test` passes (5/5) as-is.

**Status: all findings below applied.** Pre-change state tagged `before-claude-changes`.

## Summary

This is a small, well-scoped Azure Static Web Apps sample (ASCII-art generator with per-user history in Blob Storage). The security model described in `AGENTS.md`/`PLAN.md` — server-side ownership checks, managed identity for storage, no secrets in the browser — is followed correctly in the code. The main issue found is a routing/UX contradiction that likely breaks the anonymous landing experience the frontend was built for; the rest are minor robustness and hygiene items.

## Findings

### 1. High — `staticwebapp.config.json` blocks anonymous users from ever reaching the page the app builds for them

[app/staticwebapp.config.json:2-6](app/staticwebapp.config.json#L2-L6):

```json
"routes": [
  { "route": "/admin/*", "allowedRoles": ["admin"] },
  { "route": "/api/admin/*", "allowedRoles": ["admin"] },
  { "route": "/*", "allowedRoles": ["authenticated"] }
]
```

The fallback rule `"/*": ["authenticated"]` applies to *every* request the Static Web Apps platform serves, including static assets and `/` itself — not just API routes. That means an anonymous visitor is turned away by the platform (401/redirect) before `index.html` is ever served.

But [app/index.html:20-25](app/index.html#L20-L25) and [app/app.js:71-86](app/app.js#L71-L86) implement a client-side "signed-out" landing state (`#signed-out` section with a "Sign in with Microsoft" button, shown when `/.auth/me` returns no principal). That code path is dead: a fully anonymous user can never load the page to see it, because the route rule already gated the page load itself.

This also contradicts `PLAN.md`'s own build step: *"Build the static user interface: sign-in state, generator form..."* — the sign-in state was clearly intended to be reachable.

**Fix:** scope the authenticated requirement to the app shell/API routes that actually need it (e.g. `/api/*`) and leave `/`, static assets exempt, or add a `responseOverrides` 401 → `/.auth/login/aad` redirect if fully gating the site is intentional. Worth confirming against a real deployment since SWA role-route behavior can't be exercised locally.

**Applied:** `routes` now only gates `/api/*` (authenticated) and `/api/admin/*` (admin); static assets and `/` are unrestricted so the anonymous landing state can render. Dropped the unused `/admin/*` rule — there is no such page in this single-page app.

### 2. Medium — `generate.js` maps all non-auth failures to 400, including real server errors

[api/src/functions/generate.js:25-27](api/src/functions/generate.js#L25-L27):

```js
} catch (error) {
  return { status: error.message === "Authentication is required." ? 401 : 400, jsonBody: { error: error.message } };
}
```

`validateGenerationRequest` throwing is correctly a 400. But the same catch also wraps `renderAsciiArt` and `createSession` — e.g. a missing `STORAGE_ACCOUNT_NAME`, a managed-identity/RBAC failure, or a Blob Storage outage ([api/src/services/session-store.js:10-12](api/src/services/session-store.js#L10-L12)) — and reports those to the client as "Bad Request" too. That's misleading to users and makes infra misconfiguration harder to diagnose from client-visible symptoms alone. `sessions.js`/`admin-sessions.js` already get this right (auth → 401, everything else → 500).

**Fix:** throw a distinguishable error (or a typed/tagged error) from `validateGenerationRequest` and only map *that* to 400; let other exceptions fall through to 500.

**Applied:** added a `ValidationError` class in `ascii-renderer.js`; `generate.js` now returns 400 only for `ValidationError`, 401 for the auth error, and 500 for anything else (Blob Storage/config failures included).

### 3. Low — session IDs aren't format-validated before being used in blob names

[api/src/services/session-store.js:24-26](api/src/services/session-store.js#L24-L26) builds the blob name as `sessions/${encodeURIComponent(ownerId)}/${sessionId}.json`, but `sessionId` (from the route parameter in [api/src/functions/sessions.js:22-31](api/src/functions/sessions.js#L22-L31)) is never validated as a UUID or otherwise sanitized before use.

This isn't an exploitable path-traversal — Azure Blob names are flat strings with no path normalization, so a `sessionId` containing `../` or `/` just becomes a literal (and almost certainly non-existent) blob name under the caller's own `ownerId` prefix; the ownership check via `getSession`/`isSessionOwner` still holds. But it's cheap, standard hardening to validate the shape of user-controlled input before it reaches a storage API, and it gives cleaner errors than whatever the Blob SDK does with a malformed name.

**Fix:** validate `sessionId` matches the UUID format `generate.js` produces before calling `getSession`/`deleteSession`.

**Applied:** added `isValidSessionId` (UUID regex) in `session-store.js`; `deleteSession`'s route handler in `sessions.js` now returns 404 immediately for a malformed `sessionId` instead of reaching the Blob SDK.

### 4. Low — unbounded, sequential session listing

[api/src/services/session-store.js:51-67](api/src/services/session-store.js#L51-L67): both `listSessions` and `listAllSessions` iterate every blob under a prefix and `await` a full download per blob, one at a time, with no pagination or limit. `listAllSessions` (the admin endpoint) scans the entire `sessions/` prefix across *all* users on every call.

This is fine at lab scale but won't hold up once real usage accumulates — `TODO.md` already flags retention/lifecycle policy as deferred work, which is the right place to solve this, but it's worth calling out that the admin history view has no pagination even at the API-response level, so the fix will need a client-side change too.

**Applied (partial):** `listSessions`/`listAllSessions` now download blobs concurrently via `Promise.all` instead of one at a time, cutting wall-clock time for both endpoints. Pagination/limits are a bigger API-contract change and are intentionally left for the retention-policy work already tracked in `TODO.md`.

### 5. Low — App registration client secret grows unbounded on redeploys

[infra/deploy.ps1:49](infra/deploy.ps1#L49):

```powershell
$clientSecret = (& az ad app credential reset --id $appId --append --display-name "static-web-app" --query password --output tsv).Trim()
```

This line runs unconditionally on every `deploy.ps1` run, whether the app registration is newly created or reused (`--append` adds a new secret rather than replacing). Re-running the deploy script repeatedly (e.g. in CI, per `TODO.md`'s "Add CI/CD" follow-up) will accumulate credentials on the app registration indefinitely since nothing prunes old ones.

**Fix:** either drop `--append` when reusing an existing `$appId`, or add a cleanup step that removes expired/superseded secrets.

**Applied:** when `$appId` is reused, `deploy.ps1` now deletes all existing password credentials on the app registration before `credential reset --append` issues a fresh one, so redeploys no longer accumulate secrets.

## What's solid

- Ownership and admin authorization are enforced server-side in every handler ([api/src/services/authorization.js](api/src/services/authorization.js)), not just via the SWA route config — matches the "second layer of defense" design in `PLAN.md`.
- The API is the only place `figlet` and Blob Storage are touched, exactly per `AGENTS.md`'s security rules; nothing in `app/` reaches storage directly or receives credentials.
- `DefaultAzureCredential` + system-assigned managed identity for Blob access, no shared keys or connection strings — `main.bicep` also explicitly sets `allowSharedKeyAccess: false`.
- Frontend renders all user-controlled text via `textContent` (never `innerHTML`), so there's no stored/reflected XSS path for session text or art despite storing user-supplied strings.
- Test coverage in `api/test/services.test.js` hits the right seams: validation, principal parsing, role mapping, and ownership — matching the "cover authentication, authorization, input validation, ownership" convention in `AGENTS.md`.
- `staticwebapp.config.json`'s tenant-placeholder swap-and-restore in `deploy.ps1` is handled with a `try/finally`, so a failed deploy won't leave `__TENANT_ID__` permanently replaced in source control.
