import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { renderAsciiArt, validateGenerationRequest } from "../src/services/ascii-renderer.js";
import { getPrincipal, isSessionOwner, requireAdmin, resolveRoles } from "../src/services/authorization.js";
import { createSession, deleteSession, getSession, listAllSessions, listSessions } from "../src/services/session-store.js";

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

test("uses a fixed local principal and filesystem session store in local development", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "typecast-sessions-"));
  const previousEnvironment = {
    LOCAL_DEVELOPMENT: process.env.LOCAL_DEVELOPMENT,
    LOCAL_USER_ID: process.env.LOCAL_USER_ID,
    SESSION_STORE: process.env.SESSION_STORE,
    SESSIONS_FILE_SYSTEM_PATH: process.env.SESSIONS_FILE_SYSTEM_PATH
  };

  process.env.LOCAL_DEVELOPMENT = "true";
  process.env.LOCAL_USER_ID = "local-test-user";
  process.env.SESSION_STORE = "filesystem";
  process.env.SESSIONS_FILE_SYSTEM_PATH = directory;

  try {
    assert.deepEqual(getPrincipal(new Request("https://example.test/api/sessions")), {
      objectId: "local-test-user",
      roles: ["authenticated", "user", "admin"],
      groups: []
    });

    const session = {
      id: "00000000-0000-4000-8000-000000000001",
      ownerId: "local-test-user",
      text: "Hello",
      font: "Small",
      art: "Hello",
      createdAt: "2026-09-07T00:00:00.000Z"
    };
    await createSession(session);
    assert.deepEqual(await getSession(session.ownerId, session.id), session);
    assert.deepEqual(await listSessions(session.ownerId), [session]);
    assert.deepEqual(await listAllSessions(), [session]);
    await deleteSession(session.ownerId, session.id);
    assert.equal(await getSession(session.ownerId, session.id), null);
  } finally {
    await rm(directory, { recursive: true, force: true });
    for (const [key, value] of Object.entries(previousEnvironment)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
});
