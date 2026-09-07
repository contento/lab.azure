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

---

## Second pass — 2026-09-07

Two commits landed since the first pass, both after `before-claude-changes`:

- `92b5a5b` — added [`DEEPSEEK-REVIEW.md`](../DEEPSEEK-REVIEW.md) (repo root), an independent review pass by a different model. It confirms all five findings above are correctly applied and adds its own findings (S1-S2, T1-T5, F1-F3, I1-I4) — mostly error-classification robustness (string-matching exception messages instead of typed errors, a couple of 500s that should be 400s, raw `error.message` echoed to the client on unexpected failures) and low/info-grade polish. None of it is a live security hole; I largely agree with its assessment and it's worth working through as a follow-up (see recommendation below), but it doesn't change anything applied in the first pass.
- `6e89bc6` — added a filesystem-backed local development mode (`SESSION_STORE=filesystem`, `LOCAL_DEVELOPMENT=true`) so `npx swa start` works without Entra or Azure Storage. This is new code, not covered by either prior review, and introduces one finding worth fixing before relying on it further.
- `849e1e9` — landed after this second pass started (`feat: add local and deployment helpers`): adds root-level `start-local.sh`/`.ps1` and `deploy.sh`/`.ps1` wrappers, and renames the admin endpoint from `/api/admin/sessions` to `/api/sessions/admin`. Checked the rename for consistency — `admin-sessions.js`'s route, `staticwebapp.config.json`'s route rule, and `app.js`'s fetch call were all updated together, so it's a deliberate, correctly-applied rename, not a regression. It also extends `resolveRoles()` with the same `isLocalDevelopment()` short-circuit already in `getPrincipal()` — one more reason finding 6 below is worth closing: the local-dev bypass now controls both identity *and* role resolution.

**Checkpoint before this pass:** tagged `before-claude-second-review`.

### 6. High — `LOCAL_DEVELOPMENT=true` is an unauthenticated-admin backdoor if it ever reaches a real deployment

[api/src/services/authorization.js:5-30](api/src/services/authorization.js#L5-L30):

```js
function isLocalDevelopment() {
  return process.env.LOCAL_DEVELOPMENT === "true";
}

function localPrincipal() {
  const roles = (process.env.LOCAL_USER_ROLES ?? "authenticated,user,admin")...
  return { objectId: process.env.LOCAL_USER_ID ?? "local-developer", roles, groups: [] };
}

export function getPrincipal(request) {
  const clientPrincipalHeader = request.headers.get("x-ms-client-principal");
  if (!clientPrincipalHeader) {
    return isLocalDevelopment() ? localPrincipal() : null;
  }
  ...
```

`getPrincipal` is the single source of identity for every API handler (`generate`, `sessions`, `admin-sessions`, `GetRoles`). The only thing standing between "unauthenticated request" and "fully-privileged admin" is one environment variable, and `local.settings.example.json` — the file `README.md` tells developers to copy — ships it as `LOCAL_DEVELOPMENT=true` with `LOCAL_USER_ROLES=authenticated,user,admin` by default. There is nothing in the code that checks whether it's actually running locally (e.g. absence of `WEBSITE_SITE_NAME`/`FUNCTIONS_EXTENSION_VERSION`, which Azure sets and a local `func`/`swa` host does not). If this flag is ever set in the deployed Static Web App's application settings — copy-pasted from the local file, carried over by a CI script, or set by mistake during troubleshooting — every request without an `x-ms-client-principal` header (i.e. every anonymous request, since the header only exists once SWA's own auth has run) is treated as a fully-privileged local-developer admin. That's a complete authentication bypass, not a degraded-security edge case.

`deploy.ps1`'s `appsettings set` call doesn't set this variable today, so a `deploy.ps1` run won't introduce it — but nothing actively prevents or clears it either, and the blast radius (full admin, no auth) is high enough that "the deploy script happens not to set it" isn't a comfortable safety margin on its own.

**Fix:** make the local-dev fallback self-disabling in a real Azure environment, not just absent from the deploy script — e.g. `isLocalDevelopment() { return process.env.LOCAL_DEVELOPMENT === "true" && !process.env.WEBSITE_SITE_NAME; }` (Azure Functions/App Service always sets `WEBSITE_SITE_NAME`; a local `func start`/`swa start` host never does). Add a test asserting the fallback is refused when that indicator is present, and add a line to `README.md`/`AGENTS.md` warning never to copy `LOCAL_DEVELOPMENT`/`LOCAL_USER_ROLES` into deployed app settings.

### 7. Medium — filesystem session store has no defense-in-depth against a malicious `sessionId`

[api/src/services/session-store.js:19-21](api/src/services/session-store.js#L19-L21):

```js
function sessionFilePath(ownerId, sessionId) {
  return path.join(sessionDirectory(), encodeURIComponent(ownerId), `${sessionId}.json`);
}
```

Unlike Blob Storage (a flat namespace where `../` in a blob name is just a literal character, as noted in finding 3), `path.join` on a real filesystem *does* resolve `..` segments. `ownerId` is encoded but `sessionId` is not. Today this is safe only because the one caller that passes a route-supplied `sessionId` — `deleteSession` in [api/src/functions/sessions.js:22-31](api/src/functions/sessions.js#L26-L28) — already rejects non-UUID input via the `isValidSessionId` check added in finding 3. In other words, the fix from the first pass happens to also be the only thing preventing local-filesystem path traversal (arbitrary file read via `getSession`, arbitrary file delete via `deleteSession`) now that a real filesystem backend exists. That's a fragile arrangement: the store itself trusts its caller completely, so any future code path that reaches `getSession`/`deleteSession` with unvalidated input (a new endpoint, a refactor that moves the check, a different caller in a test or script) reopens it with no second line of defense.

**Fix:** validate `sessionId` inside `session-store.js` itself (reuse `isValidSessionId`, e.g. in `sessionFilePath`, throwing or returning `null` on a bad ID) so the store is safe independent of what handlers do upstream. Cheap, and consistent with the module already being the sole place storage concerns live per `AGENTS.md`.

### Recommendation

Yes, worth re-executing — finding 6 is a real (if currently dormant) authentication-bypass risk and finding 7 is a cheap hardening pass on code introduced since the last apply. Both are small, contained changes. `DEEPSEEK-REVIEW.md`'s T1/T2/T3 (typed auth errors, JSON-parse error mapping, no raw `error.message` to the client) are good follow-ups in the same spirit as this pass's finding 2 and would be reasonable to fold in at the same time, but aren't urgent — the rest of that review (F1-F3, I1-I4, S2) is polish appropriate to leave for later.
