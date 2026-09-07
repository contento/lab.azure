# Code Review: Typecast (`static-web-app-ascii`)

Reviewed: 2026-09-07
Reviewer: DeepSeek (independent pass)
Scope: only [`static-web-app-ascii/`](static-web-app-ascii) — `app/`, `api/`, `infra/`, and project docs.
Method: full read of source, tests, and IaC, plus live verification (`npm test`, `npm run lint`).

## Verification performed

| Check | Command | Result |
| --- | --- | --- |
| API unit tests | `npm test` (`node --test`) from [`static-web-app-ascii/api/`](static-web-app-ascii/api) | 5/5 pass |
| API syntax lint | `npm run lint` (`node --check` on both service files) | pass |

Working tree left clean.

## Relationship to the existing CLAUDE-REVIEW.md

[`CLAUDE-REVIEW.md`](static-web-app-ascii/CLAUDE-REVIEW.md) already exists inside the module and its five findings were applied to the code (tagged `before-claude-changes`). This review is an independent second pass. I confirm each of those fixes is present in the current code:

- Route config gates only `/api/*` (authenticated) and `/api/admin/*` (admin); static assets and `/` are open so the anonymous landing state renders — [`app/staticwebapp.config.json:2-5`](static-web-app-ascii/app/staticwebapp.config.json#L2-L5).
- Typed `ValidationError` added and `generate.js` now returns 400 only for it (401 for auth, 500 otherwise) — [`ascii-renderer.js:6`](static-web-app-ascii/api/src/services/ascii-renderer.js#L6), [`generate.js:25-33`](static-web-app-ascii/api/src/functions/generate.js#L25-L33).
- Session IDs UUID-validated before delete reaches Blob — [`session-store.js:8-10`](static-web-app-ascii/api/src/services/session-store.js#L8-L10), [`sessions.js:26-28`](static-web-app-ascii/api/src/functions/sessions.js#L26-L28).
- Session listing downloads blobs concurrently — [`session-store.js:56-63`](static-web-app-ascii/api/src/services/session-store.js#L56-L63).
- Redeploys prune superseded app-registration credentials — [`infra/deploy.ps1:46-51`](static-web-app-ascii/infra/deploy.ps1#L46-L51).

Findings below are **new or residual** after that prior pass.

---

## Executive summary

Typecast is a small, cleanly-scoped Azure Static Web Apps sample: a vanilla HTML/CSS/JS frontend plus a Node.js Functions v4 API that renders ASCII art with `figlet` and persists each signed-in user's history to Azure Blob Storage under `sessions/<Entra-object-id>/<session-id>.json`. Authentication is a custom Microsoft Entra ID provider; roles (`user`/`admin`) come from deployment-created security groups via a `rolesSource` endpoint. All storage access uses the SWA system-assigned managed identity with RBAC (`Storage Blob Data Contributor`); the browser never sees credentials or touches Blob directly.

The security design is sound and followed correctly in code — server-side ownership checks, admin read-only, XSS-safe rendering, no secrets in the browser. The issues I found are mostly **robustness/error-handling** and **operational** concerns rather than security holes:

- Error classification in the API still relies on **string-matching exception messages**, which is brittle (the validation side already moved to typed errors; the auth side should follow).
- Malformed JSON and a few other client errors can surface as **500 instead of 400**.
- Two endpoints **echo internal `error.message` text to the browser** on server failures, which is inconsistent with `generate.js`'s generic message and can leak storage/config detail.
- A handful of hardening/polish items in the frontend, IaC, and deploy script.

Severity key: **High** = fix before production use · **Medium** = correct soon · **Low** = polish/hardening · **Info** = observation.

---

## Findings

### Security & trust model

#### S1 (Low) — Authorization ultimately trusts a header value; safe only because SWA is the sole ingress

Every handler derives identity from the `x-ms-client-principal` request header ([`authorization.js:10`](static-web-app-ascii/api/src/services/authorization.js#L10)) which the Static Web Apps platform injects *after* validating the session — it is not browser-supplied. This is the correct SWA pattern and the deployment keeps Functions reachable only through the SWA `/api` proxy (the config `authLevel: "anonymous"` on every trigger is deliberate; SWA route rules plus the in-handler `requirePrincipal` are the actual guards).

**Residual risk / note:** if the underlying Function App were ever exposed directly (e.g., a future BYO-Functions migration with a public endpoint), the header could be forged and `authLevel: "anonymous"` would offer no protection. Consider documenting that this sample is only safe while Functions stays behind the SWA-managed gateway, and (if ever exported) moving to `authLevel: "function"`/EasyAuth-style validation.

#### S2 (Info) — `getPrincipal` reads roles from two sources with conflicting precedence

[`authorization.js:19`](static-web-app-ascii/api/src/services/authorization.js#L19) prefers a `userRoles` *claim* (`claimValues(claims, "userRoles")[0]?.split(",")`) and only falls back to `principal.userRoles`. In the real SWA v2 client-principal shape, roles arrive in the top-level `userRoles` array (produced by the `rolesSource`), not as a claim of type `userRoles`; meanwhile admin/user derivation for the rolesSource itself is done from `groups` claims in `resolveRoles` ([`authorization.js:47-58`](static-web-app-ascii/api/src/services/authorization.js#L47-L58)). So in the deployed shape the fallback path is what actually runs, but the code expresses two overlapping sources with the (probably inert) claim path winning if both exist. It is harmless today but confusing, and the tests only exercise the claim path ([`test/services.test.js:28-39`](static-web-app-ascii/api/test/services.test.js#L28-L39)).

**Fix (low):** pick one authoritative role source, document it, and add a unit test covering the `principal.userRoles` array fallback so the real deployment path is locked in.

---

### API robustness & error handling

#### T1 (Medium) — Auth/admin failures are classified by string-matching `error.message`

`generate.js`, `sessions.js`, and `admin-sessions.js` branch on literal messages: `"Authentication is required."` ([`generate.js:26`](static-web-app-ascii/api/src/functions/generate.js#L26), [`sessions.js:14`](static-web-app-ascii/api/src/functions/sessions.js#L14), [`sessions.js:36`](static-web-app-ascii/api/src/functions/sessions.js#L36), [`admin-sessions.js:15`](static-web-app-ascii/api/src/functions/admin-sessions.js#L15)) and `"Administrator access is required."` ([`admin-sessions.js:15`](static-web-app-ascii/api/src/functions/admin-sessions.js#L15)). The prior fix introduced a typed `ValidationError`, but the auth path still depends on message equality. Consequences:

- Editing the wording in [`authorization.js:31`](static-web-app-ascii/api/src/services/authorization.js#L31) or [`authorization.js:40`](static-web-app-ascii/api/src/services/authorization.js#L40) silently turns auth failures into 500s.
- Any thrown error whose message happens to equal those strings is misclassified (e.g., a dependency message that coincidentally matches).

**Fix:** mirror the validation approach — define `AuthenticationRequiredError` / `AuthorizationError` (thrown by [`requirePrincipal`](static-web-app-ascii/api/src/services/authorization.js#L28-L35) and [`requireAdmin`](static-web-app-ascii/api/src/services/authorization.js#L37-L41)) and `catch` by type. Add handler-level tests asserting the 401/403/400/500 mapping; today only pure services are tested.

#### T2 (Medium) — Malformed JSON body returns 500 instead of 400

[`generate.js:14`](static-web-app-ascii/api/src/functions/generate.js#L14) calls `await request.json()` inside the `try` but outside the `ValidationError` flow. A body that isn't valid JSON throws `SyntaxError`, which the catch at [`generate.js:25-33`](static-web-app-ascii/api/src/functions/generate.js#L25-L33) reports as a generic 500. The first-party frontend always sends valid JSON, so this is robustness rather than a live bug — but any direct/scripted caller of the same-origin endpoint gets a misleading 500 for a client mistake.

**Fix:** wrap the parse and map `SyntaxError` to a 400 ("Request body must be valid JSON"), ideally as another typed error handled alongside `ValidationError`.

#### T3 (Low/Medium) — `sessions.js` and `admin-sessions.js` echo raw internal errors to the browser on 500

[`generate.js:32`](static-web-app-ascii/api/src/functions/generate.js#L32) deliberately returns a generic message for unexpected errors, but the other endpoints return the raw exception: [`sessions.js:13-15`](static-web-app-ascii/api/src/functions/sessions.js#L13-L15), [`sessions.js:35-38`](static-web-app-ascii/api/src/functions/sessions.js#L35-L38), and [`admin-sessions.js:14-17`](static-web-app-ascii/api/src/functions/admin-sessions.js#L14-L17) send `jsonBody: { error: error.message }` on the 500 path. A Blob Storage/RBAC failure can embed the storage account URL or SDK internals, surfacing them to an authenticated user — inconsistent with the generic-message hygiene used elsewhere and with the security posture described in [`AGENTS.md`](static-web-app-ascii/AGENTS.md#L15-L19).

**Fix:** return a generic 500 to the client and log the real error server-side (Application Insights). Consider a tiny shared `toHttpError` helper so all four handlers classify consistently.

#### T4 (Info) — Corrupt blob breaks the whole history listing

[`downloadSession`](static-web-app-ascii/api/src/services/session-store.js#L33-L37) does `JSON.parse(body)` without catching parse errors, and [`downloadSessionsByPrefix`](static-web-app-ascii/api/src/services/session-store.js#L56-L63) fans that out over `Promise.all`. A single truncated/corrupt session blob (e.g., an interrupted upload) makes the entire `listSessions` or `listAllSessions` call fail with 500, blanking history for the user (or for admins across *all* users). Blob is private and only written by this app, so corruption is unlikely — but once lifecycle/retention is added (see [`TODO.md`](static-web-app-ascii/TODO.md#L19-L21)) or external tooling touches the container, this becomes realistic.

**Fix (low):** skip (or quarantine) individual blobs that fail to parse rather than failing the whole listing; at minimum log and continue.

#### T5 (Info) — Unbounded writes; generate has no rate limit or quota

Each successful `POST /api/generate` creates a new blob with a fresh UUID ([`generate.js:15-23`](static-web-app-ascii/api/src/functions/generate.js#L15-L23)) and nothing bounds how many a single user can create. `TODO.md` already defers retention/lifecycle policy and this was flagged in the prior review on the read side (unbounded listing). The write side has the same growth profile: any authenticated user can accumulate unlimited small blobs at no per-user cost to themselves. Fine at lab scale; worth pairing a lifecycle policy with an optional per-user cap or rate limit before any real multi-user use.

---

### Frontend

#### F1 (Low) — Delete button swallows failures (no error UX)

The Delete handler at [`app.js:50-53`](static-web-app-ascii/app/app.js#L50-L53) `await`s the DELETE then reloads history with no `try/catch` and no user-visible error surface. A failed delete becomes an unhandled promise rejection and the UI gives no feedback. The generate path ([`app.js:88-107`](static-web-app-ascii/app/app.js#L88-L107)) handles errors correctly and shows them in `#form-error`; mirror that pattern for delete (e.g., a shared error banner).

#### F2 (Info) — No security headers on static responses

[`app/staticwebapp.config.json`](static-web-app-ascii/app/staticwebapp.config.json) defines routes and auth only — no `globalHeaders`/`responseOverrides`. Adding `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, and `Referrer-Policy` via SWA response overrides is cheap hardening. XSS risk is already mitigated (all user text is rendered through `textContent`, never `innerHTML` — see [`app.js:23`](static-web-app-ascii/app/app.js#L23), [`app.js:35`](static-web-app-ascii/app/app.js#L35)); this is defense-in-depth, not a fix for a known hole.

#### F3 (Info) — Minor observations

- `fetch` calls have no timeout/abort; a hung request leaves the Generate button disabled only while awaiting (it re-enables in `finally`), but an unresponsive `/.auth/me` at startup would leave the signed-out view with no recovery path ([`app.js:72`](static-web-app-ascii/app/app.js#L72)).
- Admin detection uses the browser-visible `principal.userRoles` ([`app.js:77`](static-web-app-ascii/app/app.js#L77)) for UI only; data access is still gated server-side, which matches the documented boundary — good.
- Accessibility is solid (labels, `role="alert"`, `aria-live`, visually-hidden label for the font select in [`index.html`](static-web-app-ascii/app/index.html#L38)), no changes needed.

---

### Infrastructure & deployment

#### I1 (Info) — Bicep documents but doesn't enforce storage-name constraints

[`main.bicep:7-8`](static-web-app-ascii/infra/main.bicep#L7-L8) documents that `storageAccountName` must be 3–24 lowercase alphanumerics but adds no `@minLength/@maxLength` decorators, so the failure surfaces as a raw Azure CLI error at deploy time rather than at `az bicep build` time. Cheap to add.

#### I2 (Info) — Redeploy cleanup deletes *all* credentials on a reused app registration

[`deploy.ps1:47-50`](static-web-app-ascii/infra/deploy.ps1#L47-L50) lists and deletes every password credential on the app registration before issuing a fresh one with `credential reset --append`. This correctly fixes secret accumulation, but it will also revoke any secret another consumer/environment legitimately holds on that same registration. It is safe for the intended dedicated `*-auth` registration; add a comment or guard if the app ID could ever be shared.

#### I3 (Info) — Client secret travels as a command-line argument

[`deploy.ps1:53-55`](static-web-app-ascii/infra/deploy.ps1#L53-L55) captures the secret from `az ad app credential reset` and passes it into `az staticwebapp appsettings set --setting-names "AZURE_CLIENT_SECRET=$clientSecret"`, so the value can appear in process listings or shell history on some hosts. Acceptable for a lab; the production-grade alternative is storing it in Key Vault and using a Key Vault reference in the SWA app settings.

#### I4 (Info) — No explicit `navigationFallback` or custom 404

[`staticwebapp.config.json`](static-web-app-ascii/app/staticwebapp.config.json) doesn't define a `navigationFallback`. Since this is a single page served at `/` with no client-side routes, that's fine today — only relevant if deep links or an SPA router are added later.

---

## What's solid

- **Authorization is authoritative in the API, not just in route config.** Ownership checks and admin gating run in every handler ([`authorization.js`](static-web-app-ascii/api/src/services/authorization.js), [`sessions.js`](static-web-app-ascii/api/src/functions/sessions.js), [`admin-sessions.js`](static-web-app-ascii/api/src/functions/admin-sessions.js)); SWA route rules are explicitly a second layer per [`PLAN.md`](static-web-app-ascii/PLAN.md#L37).
- **The browser never touches secrets or storage.** `figlet`, Blob Storage, and all credentials live only in the API, matching [`AGENTS.md`](static-web-app-ascii/AGENTS.md#L15-L16); nothing in `app/` receives storage keys.
- **Managed identity + RBAC-only storage.** [`main.bicep`](static-web-app-ascii/infra/main.bicep) sets `allowSharedKeyAccess: false`, `allowBlobPublicAccess: false`, `minimumTlsVersion: TLS1_2`, HTTPS-only, and grants the SWA identity `Storage Blob Data Contributor` through a scoped role assignment.
- **XSS-safe rendering.** Every user-controlled string (session text, art, metadata) is inserted via `textContent`; `innerHTML` is never used, so stored/reflected XSS has no viable path despite storing arbitrary user text.
- **Input validation is server-side.** 80-char text cap, required text, and a font allow-list live in [`ascii-renderer.js:8-28`](static-web-app-ascii/api/src/services/ascii-renderer.js#L8-L28); the client `maxlength` is only a convenience.
- **Deployment hygiene.** The `__TENANT_ID__` placeholder swap in the config is wrapped in `try/finally` so a failed deploy can't leave the checked-in template mutated ([`deploy.ps1:57-68`](static-web-app-ascii/infra/deploy.ps1#L57-L68)); the deployment token is held only in process memory; sensitive files are gitignored.
- **Tests target the right seams** (validation, principal parsing, role mapping, ownership) and pass 5/5; the pure-service split makes the logic testable without Azure.
- **Documentation is unusually good for a lab** — README/AGENTS/PLAN/TODO give an accurate map of intent, security boundaries, and deferred work.

---

## Suggested priority

1. **T1 + T2** — finish the typed-error refactor (auth/admin errors + JSON parse), add handler-level tests for status mapping.
2. **T3** — stop echoing internal `error.message` to the browser; log server-side instead.
3. **F1** — surface delete failures in the UI.
4. **S2, T4, T5, I1-I4** — low-effort hardening/documentation when convenient.
5. Everything else is Info-grade polish appropriate to leave as-is for a lab sample.
