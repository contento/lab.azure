import { DefaultAzureCredential } from "@azure/identity";
import { BlobServiceClient } from "@azure/storage-blob";

const containerName = process.env.SESSIONS_CONTAINER_NAME ?? "sessions";
const sessionIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
let containerClient;

export function isValidSessionId(sessionId) {
  return typeof sessionId === "string" && sessionIdPattern.test(sessionId);
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
  const client = getContainerClient();
  return downloadSessionsByPrefix(client, `sessions/${encodeURIComponent(ownerId)}/`);
}

export async function listAllSessions() {
  const client = getContainerClient();
  return downloadSessionsByPrefix(client, "sessions/");
}

export async function getSession(ownerId, sessionId) {
  const client = getContainerClient();
  const name = blobName(ownerId, sessionId);
  const blob = client.getBlobClient(name);
  if (!(await blob.exists())) {
    return null;
  }
  return downloadSession(client, name);
}

export async function deleteSession(ownerId, sessionId) {
  const client = getContainerClient();
  await client.deleteBlob(blobName(ownerId, sessionId), { deleteSnapshots: "include" });
}
