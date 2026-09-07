const state = { art: "", isAdmin: false };

const elements = {
  signedOut: document.querySelector("#signed-out"), workspace: document.querySelector("#workspace"),
  accountName: document.querySelector("#account-name"), signIn: document.querySelector("#sign-in"), signOut: document.querySelector("#sign-out"),
  form: document.querySelector("#generator-form"), text: document.querySelector("#source-text"), font: document.querySelector("#font"),
  error: document.querySelector("#form-error"), output: document.querySelector("#ascii-output"), copy: document.querySelector("#copy-result"),
  download: document.querySelector("#download-result"), history: document.querySelector("#history-list"), historyEmpty: document.querySelector("#history-empty"),
  adminSection: document.querySelector("#admin-section"), adminHistory: document.querySelector("#admin-history-list"), adminEmpty: document.querySelector("#admin-empty")
};

async function request(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error ?? "The request could not be completed.");
  }
  return response.status === 204 ? null : response.json();
}

function displayArt(art) {
  state.art = art;
  elements.output.textContent = art || "Your generated text will appear here.";
  elements.copy.disabled = !art;
  elements.download.disabled = !art;
}

function renderHistory(list, sessions, canDelete) {
  list.replaceChildren();
  for (const session of sessions) {
    const item = document.createElement("li");
    const meta = document.createElement("div");
    const title = document.createElement("strong");
    const details = document.createElement("span");
    title.textContent = session.text;
    details.textContent = `${session.font} | ${new Date(session.createdAt).toLocaleString()}`;
    meta.append(title, details);
    item.append(meta);
    const preview = document.createElement("button");
    preview.className = "button button-quiet";
    preview.type = "button";
    preview.textContent = "View";
    preview.addEventListener("click", () => displayArt(session.art));
    item.append(preview);
    if (canDelete) {
      const remove = document.createElement("button");
      remove.className = "button button-danger";
      remove.type = "button";
      remove.textContent = "Delete";
      remove.addEventListener("click", async () => {
        await request(`/api/sessions/${encodeURIComponent(session.id)}`, { method: "DELETE" });
        await loadHistory();
      });
      item.append(remove);
    }
    list.append(item);
  }
}

async function loadHistory() {
  const sessions = await request("/api/sessions");
  renderHistory(elements.history, sessions, true);
  elements.historyEmpty.hidden = sessions.length > 0;
  if (state.isAdmin) {
    const allSessions = await request("/api/admin/sessions");
    renderHistory(elements.adminHistory, allSessions, false);
    elements.adminEmpty.hidden = allSessions.length > 0;
  }
}

async function initialize() {
  const response = await fetch("/.auth/me");
  const data = response.ok ? await response.json() : [];
  const principal = data.clientPrincipal ?? data[0]?.clientPrincipal;
  const isLocalHost = ["localhost", "127.0.0.1", "::1"].includes(window.location.hostname);
  if (!principal && !isLocalHost) return;

  const roles = principal?.userRoles ?? (await request("/api/GetRoles")).roles;

  state.isAdmin = roles.some((role) => role.toLowerCase() === "admin");
  elements.signedOut.hidden = true;
  elements.workspace.hidden = false;
  elements.accountName.textContent = principal?.userDetails ?? "Local developer";
  elements.accountName.hidden = false;
  elements.signIn.hidden = true;
  elements.signOut.hidden = false;
  elements.adminSection.hidden = !state.isAdmin;
  await loadHistory();
}

elements.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  elements.error.hidden = true;
  const submit = elements.form.querySelector("button[type=submit]");
  submit.disabled = true;
  try {
    const session = await request("/api/generate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: elements.text.value, font: elements.font.value })
    });
    displayArt(session.art);
    await loadHistory();
  } catch (error) {
    elements.error.textContent = error.message;
    elements.error.hidden = false;
  } finally {
    submit.disabled = false;
  }
});

elements.copy.addEventListener("click", () => navigator.clipboard.writeText(state.art));
elements.download.addEventListener("click", () => {
  const url = URL.createObjectURL(new Blob([state.art], { type: "text/plain" }));
  const link = Object.assign(document.createElement("a"), { href: url, download: "typecast.txt" });
  link.click();
  URL.revokeObjectURL(url);
});

initialize().catch((error) => {
  elements.error.textContent = error.message;
  elements.error.hidden = false;
});
