import assert from "node:assert/strict";
import test from "node:test";
import { renderAsciiArt, validateGenerationRequest } from "../src/services/ascii-renderer.js";
import { getPrincipal, isSessionOwner, requireAdmin, resolveRoles } from "../src/services/authorization.js";

function createRequest(principal) {
  return new Request("https://example.test/api/sessions", {
    headers: {
      "x-ms-client-principal": Buffer.from(JSON.stringify(principal)).toString("base64")
    }
  });
}

test("validates and renders server-approved ASCII requests", () => {
  const request = validateGenerationRequest({ text: "Hello", font: "Small" });
  const art = renderAsciiArt(request);

  assert.deepEqual(request, { text: "Hello", font: "Small" });
  assert.ok(art.trim().length > 0);
  assert.ok(art.split("\n").length > 1);
});

test("rejects blank text and unsupported fonts", () => {
  assert.throws(() => validateGenerationRequest({ text: "   " }), /Text is required/);
  assert.throws(() => validateGenerationRequest({ text: "Hello", font: "Untrusted" }), /not supported/);
});

test("extracts the Entra object ID and SWA roles from the authenticated principal", () => {
  const principal = getPrincipal(createRequest({
    userId: "fallback-id",
    claims: [
      { typ: "http://schemas.microsoft.com/identity/claims/objectidentifier", val: "entra-object-id" },
      { typ: "userRoles", val: "authenticated,admin" }
    ]
  }));

  assert.deepEqual(principal, { objectId: "entra-object-id", roles: ["authenticated", "admin"], groups: [] });
  assert.doesNotThrow(() => requireAdmin(principal));
});

test("enforces admin access and session ownership", () => {
  const user = { objectId: "user-a", roles: ["user"] };

  assert.throws(() => requireAdmin(user), /Administrator access/);
  assert.equal(isSessionOwner({ ownerId: "user-a" }, user), true);
  assert.equal(isSessionOwner({ ownerId: "user-b" }, user), false);
});

test("maps Entra security group claims to Static Web Apps roles", () => {
  const principal = getPrincipal(createRequest({
    userId: "user-a",
    claims: [{ typ: "groups", val: "admin-group-id" }]
  }));

  assert.deepEqual(resolveRoles(principal, "admin-group-id", "user-group-id"), ["authenticated", "admin", "user"]);
  assert.deepEqual(resolveRoles({ ...principal, groups: [] }, "admin-group-id", "user-group-id"), ["authenticated"]);
});
