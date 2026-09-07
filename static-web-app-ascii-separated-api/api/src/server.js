import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { URL } from "node:url";
import { renderAsciiArt, validateGenerationRequest, ValidationError } from "./services/ascii-renderer.js";
import { createSession, deleteSession, getSession, isValidSessionId, listSessions } from "./services/session-store.js";

const port = Number(process.env.PORT ?? 7071);
const allowedOrigin = process.env.ALLOWED_ORIGIN ?? "http://localhost:4280";

function send(response, status, body) {
  response.writeHead(status, { "access-control-allow-origin": allowedOrigin, "access-control-allow-methods": "GET,POST,DELETE,OPTIONS", "access-control-allow-headers": "content-type", "content-type": "application/json" });
  response.end(body === undefined ? undefined : JSON.stringify(body));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

const server = createServer(async (request, response) => {
  const pathname = new URL(request.url, `http://${request.headers.host}`).pathname;
  if (request.method === "OPTIONS") return send(response, 204);
  try {
    if (request.method === "GET" && pathname === "/health") return send(response, 200, { status: "ok" });
    if (request.method === "GET" && pathname === "/sessions") return send(response, 200, await listSessions());
    if (request.method === "POST" && pathname === "/generate") {
      const { text, font } = validateGenerationRequest(await readJson(request));
      const session = { id: randomUUID(), text, font, art: renderAsciiArt({ text, font }), createdAt: new Date().toISOString() };
      return send(response, 201, await createSession(session));
    }
    const sessionId = pathname.match(/^\/sessions\/([^/]+)$/)?.[1];
    if (request.method === "DELETE" && sessionId) {
      if (!isValidSessionId(sessionId) || !await getSession(sessionId)) return send(response, 404, { error: "Session not found." });
      await deleteSession(sessionId);
      return send(response, 204);
    }
    return send(response, 404, { error: "Not found." });
  } catch (error) {
    return send(response, error instanceof ValidationError ? 400 : 500, { error: error instanceof ValidationError ? error.message : "The request could not be completed." });
  }
});

server.listen(port, "127.0.0.1", () => console.log(`Typecast API listening on http://127.0.0.1:${port}`));
