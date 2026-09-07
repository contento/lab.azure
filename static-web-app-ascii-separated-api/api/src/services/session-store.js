import { promises as fs } from "node:fs";
import path from "node:path";

const sessionIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function sessionDirectory() {
  return path.resolve(process.env.SESSIONS_FILE_SYSTEM_PATH ?? ".sessions");
}

function sessionPath(sessionId) {
  return path.join(sessionDirectory(), `${sessionId}.json`);
}

export function isValidSessionId(sessionId) {
  return typeof sessionId === "string" && sessionIdPattern.test(sessionId);
}

export async function createSession(session) {
  await fs.mkdir(sessionDirectory(), { recursive: true });
  await fs.writeFile(sessionPath(session.id), JSON.stringify(session), "utf8");
  return session;
}

export async function listSessions() {
  try {
    const entries = await fs.readdir(sessionDirectory());
    const sessions = await Promise.all(entries.filter((entry) => entry.endsWith(".json"))
      .map(async (entry) => JSON.parse(await fs.readFile(path.join(sessionDirectory(), entry), "utf8"))));
    return sessions.sort((first, second) => second.createdAt.localeCompare(first.createdAt));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

export async function getSession(sessionId) {
  try {
    return JSON.parse(await fs.readFile(sessionPath(sessionId), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

export async function deleteSession(sessionId) {
  await fs.rm(sessionPath(sessionId), { force: true });
}
