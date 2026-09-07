const apiBaseUrl = window.TYPECAST_API_BASE_URL;
const form = document.querySelector("#generator-form");
const output = document.querySelector("#ascii-output");
const history = document.querySelector("#history-list");
const error = document.querySelector("#form-error");

async function request(path, options) {
  const response = await fetch(`${apiBaseUrl}${path}`, options);
  const body = response.status === 204 ? null : await response.json();
  if (!response.ok) throw new Error(body.error ?? "The request could not be completed.");
  return body;
}

function showSessions(sessions) {
  history.replaceChildren(...sessions.map((session) => {
    const item = document.createElement("li");
    item.textContent = `${session.text} (${session.font})`;
    const view = document.createElement("button"); view.textContent = "View"; view.onclick = () => { output.textContent = session.art; };
    const remove = document.createElement("button"); remove.textContent = "Delete"; remove.onclick = async () => { await request(`/sessions/${session.id}`, { method: "DELETE" }); await loadSessions(); };
    item.append(view, remove); return item;
  }));
}

async function loadSessions() { showSessions(await request("/sessions")); }
form.addEventListener("submit", async (event) => { event.preventDefault(); error.hidden = true; try { const session = await request("/generate", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: document.querySelector("#source-text").value, font: document.querySelector("#font").value }) }); output.textContent = session.art; await loadSessions(); } catch (requestError) { error.textContent = requestError.message; error.hidden = false; } });
loadSessions().catch((requestError) => { error.textContent = requestError.message; error.hidden = false; });
