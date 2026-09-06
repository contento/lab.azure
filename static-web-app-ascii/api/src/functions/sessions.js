import { app } from "@azure/functions";
import { isSessionOwner, requirePrincipal } from "../services/authorization.js";
import { deleteSession, getSession, listSessions } from "../services/session-store.js";

app.http("sessions", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "sessions",
  handler: async (request) => {
    try {
      const principal = requirePrincipal(request);
      return { jsonBody: await listSessions(principal.objectId) };
    } catch (error) {
      return { status: error.message === "Authentication is required." ? 401 : 500, jsonBody: { error: error.message } };
    }
  }
});

app.http("deleteSession", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "sessions/{sessionId}",
  handler: async (request, context) => {
    try {
      const principal = requirePrincipal(request);
      const session = await getSession(principal.objectId, request.params.sessionId);
      if (!session || !isSessionOwner(session, principal)) {
        return { status: 404, jsonBody: { error: "Session not found." } };
      }
      await deleteSession(principal.objectId, session.id);
      return { status: 204 };
    } catch (error) {
      return { status: error.message === "Authentication is required." ? 401 : 500, jsonBody: { error: error.message } };
    }
  }
});
