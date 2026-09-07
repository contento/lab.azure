import { app } from "@azure/functions";
import { requireAdmin, requirePrincipal } from "../services/authorization.js";
import { listAllSessions } from "../services/session-store.js";

app.http("adminSessions", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "sessions/admin",
  handler: async (request) => {
    try {
      const principal = requirePrincipal(request);
      requireAdmin(principal);
      return { jsonBody: await listAllSessions() };
    } catch (error) {
      const status = error.message === "Authentication is required." ? 401 : error.message === "Administrator access is required." ? 403 : 500;
      return { status, jsonBody: { error: error.message } };
    }
  }
});
