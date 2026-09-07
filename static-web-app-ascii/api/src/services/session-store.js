import { DefaultAzureCredential } from "@azure/identity";
import { BlobServiceClient } from "@azure/storage-blob";
import { promises as fs } from "node:fs";
import path from "node:path";

const containerName = process.env.SESSIONS_CONTAINER_NAME ?? "sessions";
const sessionIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
let containerClient;

export function isValidSessionId(sessionId) {
  return typeof sessionId === "string" && sessionIdPattern.test(sessionId);
}

function usesFileSystemStore() {
  return process.env.SESSION_STORE === "filesystem";
}

function sessionDirectory() {
  return path.resolve(process.env.SESSIONS_FILE_SYSTEM_PATH ?? ".sessions");
}

function sessionFilePath(ownerId, sessionId) {
  return path.join(sessionDirectory(), encodeURIComponent(ownerId), `${sessionId}.json`);
}

function sortSessions(sessions) {
  return sessions.sort((first, second) => second.createdAt.localeCompare(first.createdAt));
}

async function readSessionFile(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

async function createFileSession(session) {
  const filePath = sessionFilePath(session.ownerId, session.id);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(session), "utf8");
  return session;
}

async function listFileSessions(ownerId) {
  const ownerDirectory = path.join(sessionDirectory(), encodeURIComponent(ownerId));
  try {
    const entries = await fs.readdir(ownerDirectory, { withFileTypes: true });
    const sessions = await Promise.all(entries
      .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
      .map((entry) => readSessionFile(path.join(ownerDirectory, entry.name))));
    return sortSessions(sessions.filter(Boolean));
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

async function listAllFileSessions() {
  try {
    const owners = await fs.readdir(sessionDirectory(), { withFileTypes: true });
    const sessionLists = await Promise.all(owners
      .filter((entry) => entry.isDirectory())
      .map((entry) => listFileSessions(decodeURIComponent(entry.name))));
    return sortSessions(sessionLists.flat());
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

function getContainerClient() {
  if (!containerClient) {
    const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
    if (!storageAccountName) {
      throw new Error("STORAGE_ACCOUNT_NAME is not configured.");
    }

    const serviceClient = new BlobServiceClient(
      `https://${storageAccountName}.blob.core.windows.net`,
      new DefaultAzureCredential()
    );
    containerClient = serviceClient.getContainerClient(containerName);
  }

  return containerClient;
}

function blobName(ownerId, sessionId) {
  return `sessions/${encodeURIComponent(ownerId)}/${sessionId}.json`;
}

async function downloadSession(client, name) {
  const response = await client.getBlobClient(name).download();
  const body = await streamToString(response.readableStreamBody);
  return JSON.parse(body);
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

export async function createSession(session) {
  if (usesFileSystemStore()) {
    return createFileSession(session);
  }

  const client = getContainerClient();
  const name = blobName(session.ownerId, session.id);
  await client.getBlockBlobClient(name).upload(JSON.stringify(session), Buffer.byteLength(JSON.stringify(session)), {
    blobHTTPHeaders: { blobContentType: "application/json" }
  });
  return session;
}

async function downloadSessionsByPrefix(client, prefix) {
  const blobNames = [];
  for await (const blob of client.listBlobsFlat({ prefix })) {
    blobNames.push(blob.name);
  }
  const sessions = await Promise.all(blobNames.map((name) => downloadSession(client, name)));
  return sessions.sort((first, second) => second.createdAt.localeCompare(first.createdAt));
}

export async function listSessions(ownerId) {
  if (usesFileSystemStore()) {
    return listFileSessions(ownerId);
  }

  const client = getContainerClient();
  return downloadSessionsByPrefix(client, `sessions/${encodeURIComponent(ownerId)}/`);
}

export async function listAllSessions() {
  if (usesFileSystemStore()) {
    return listAllFileSessions();
  }

  const client = getContainerClient();
  return downloadSessionsByPrefix(client, "sessions/");
}

export async function getSession(ownerId, sessionId) {
  if (usesFileSystemStore()) {
    return readSessionFile(sessionFilePath(ownerId, sessionId));
  }

  const client = getContainerClient();
  const name = blobName(ownerId, sessionId);
  const blob = client.getBlobClient(name);
  if (!(await blob.exists())) {
    return null;
  }
  return downloadSession(client, name);
}

export async function deleteSession(ownerId, sessionId) {
  if (usesFileSystemStore()) {
    await fs.rm(sessionFilePath(ownerId, sessionId), { force: true });
    return;
  }

  const client = getContainerClient();
  await client.deleteBlob(blobName(ownerId, sessionId), { deleteSnapshots: "include" });
}
