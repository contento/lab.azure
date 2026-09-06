import { app } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { renderAsciiArt, validateGenerationRequest } from "../services/ascii-renderer.js";
import { requirePrincipal } from "../services/authorization.js";
import { createSession } from "../services/session-store.js";

app.http("generate", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "generate",
  handler: async (request) => {
    try {
      const principal = requirePrincipal(request);
      const { text, font } = validateGenerationRequest(await request.json());
      const session = {
        id: randomUUID(),
        ownerId: principal.objectId,
        text,
        font,
        art: renderAsciiArt({ text, font }),
        createdAt: new Date().toISOString()
      };
      await createSession(session);
      return { status: 201, jsonBody: session };
    } catch (error) {
      return { status: error.message === "Authentication is required." ? 401 : 400, jsonBody: { error: error.message } };
    }
  }
});
