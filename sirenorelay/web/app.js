let editor;
let refreshTimer;
let appStatus;
let selectedUser;
let toastTimer;
const $ = (selector) => document.querySelector(selector);

function notice(message, error = false) {
  const target = $("#message");
  target.textContent = message;
  target.classList.toggle("error", error);
  const toast = $("#toast");
  toast.textContent = message;
  toast.classList.toggle("error", error);
  toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toast.hidden = true; }, 5000);
}

async function request(path, options) {
  const response = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  const body = await response.json();
  if (!response.ok) throw new Error(body.message || "Request failed");
  return body;
}

function showEditor(status) {
  $("#onboarding").hidden = true;
  $("#workspace").hidden = false;
  $("#network").hidden = false;
  $("#state").textContent = status.configured ? "Protected" : "Manual configuration";
  $("#state").classList.add("ready");
  if (status.config !== undefined) editor.setValue(status.config);
  $("#lan-tls").checked = status.settings.lan_tls_enabled;
  $("#certificate").value = status.settings.tls_certificate;
  $("#key").value = status.settings.tls_key;
  $("#mcp-endpoint").textContent = `MCP bridge · port ${status.settings.mcp_port}`;
  renderMcpUsers();
}

function renderAppInfo(status) {
  appStatus = status;
  const endpoint = `http://${status.hostname}:${status.settings.mcp_port}/mcp`;
  $("#mcp-endpoint").textContent = `MCP bridge · ${endpoint}`;
  $("#app-version").textContent = `App version · ${status.version}`;
}

async function refresh() {
  const status = await request("./api/status");
  renderAppInfo(status);
  if (status.configured) showEditor(status);
  else {
    $("#onboarding").hidden = false;
    $("#state").textContent = "Setup required";
    refreshTimer = setTimeout(refresh, 1000);
  }
}

function configureManually() {
  clearTimeout(refreshTimer);
  showEditor({
    configured: false,
    config: "",
    settings: { lan_tls_enabled: false, tls_certificate: "fullchain.pem", tls_key: "privkey.pem", mcp_port: 8081 },
  });
  notice("Paste a complete config.yml, then save it.");
}

function setBusy(button, busy) {
  button.disabled = busy;
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function sha256(value) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function userInsertion(model) {
  const users = model.findMatches("^users:\\s*$", false, true, false, null, false)[0];
  if (!users) return null;
  for (let line = users.range.endLineNumber + 1; line <= model.getLineCount(); line += 1) {
    if (/^\S/.test(model.getLineContent(line))) return { line, column: 1, prefix: "" };
  }
  const line = model.getLineCount();
  return { line, column: model.getLineMaxColumn(line), prefix: model.getValue().endsWith("\n") ? "" : "\n" };
}

async function insertUser(event) {
  event.preventDefault();
  if (event.submitter?.value === "cancel") {
    $("#user-dialog").close();
    return;
  }
  const form = $("#new-user-form");
  if (!form.reportValidity()) return;
  const data = new FormData(form);
  const name = data.get("name").trim();
  const provider = data.get("provider").trim();
  const profile = data.get("profile").trim();
  if (![name, provider, profile].every((value) => /^[A-Za-z0-9_.-]+$/.test(value))) {
    notice("User name, provider, and profile may contain only letters, numbers, dots, hyphens, and underscores.", true);
    return;
  }
  const token = randomToken();
  const tokenHash = await sha256(token);
  const model = editor.getModel();
  const insertion = userInsertion(model);
  if (!insertion) {
    notice("Add a top-level users: section before adding an agent.", true);
    return;
  }
  const snippet = `  ${name}:\n    provider: ${provider}\n    profile: ${profile}\n    token_hash: ${tokenHash}\n`;
  editor.executeEdits("add-user", [{ range: new monaco.Range(insertion.line, insertion.column, insertion.line, insertion.column), text: insertion.prefix + snippet, forceMoveMarkers: true }]);
  $("#user-dialog").close();
  notice(`User “${name}” was added. Copy this bearer token now: ${token}`);
  renderMcpUsers();
}

function configuredUsers() {
  const model = editor.getModel();
  const users = model.findMatches("^users:\\s*$", false, true, false, null, false)[0];
  if (!users) return [];
  const names = [];
  for (let line = users.range.endLineNumber + 1; line <= model.getLineCount(); line += 1) {
    const content = model.getLineContent(line);
    if (/^\S/.test(content)) break;
    const match = content.match(/^  ([A-Za-z0-9_.-]+):\s*$/);
    if (match) names.push(match[1]);
  }
  return names;
}

function mcpConfiguration(user, token = "<paste this user's token>") {
  const endpoint = `http://${appStatus.hostname}:${appStatus.settings.mcp_port}/mcp`;
  return JSON.stringify({ name: user, url: endpoint, headers: { Authorization: `Bearer ${token}` } }, null, 2);
}

function openMcpConfiguration(user, token) {
  selectedUser = user;
  $("#mcp-dialog-title").textContent = `${user} MCP configuration`;
  $("#mcp-dialog-copy").textContent = token ? "Token rotated. Copy this configuration now, then save config.yml." : "Paste this user's bearer token in the placeholder, or rotate it to generate a replacement.";
  $("#mcp-config").value = mcpConfiguration(user, token);
  if (!$("#mcp-dialog").open) $("#mcp-dialog").showModal();
}

function renderMcpUsers() {
  const list = $("#mcp-users-list");
  list.replaceChildren();
  const users = configuredUsers();
  if (!users.length) {
    list.textContent = "Save a config with at least one user to create MCP client configurations.";
    return;
  }
  for (const user of users) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "user-config";
    button.textContent = user;
    button.addEventListener("click", () => openMcpConfiguration(user));
    list.append(button);
  }
}

async function rotateSelectedUserToken() {
  const model = editor.getModel();
  const users = model.findMatches("^users:\\s*$", false, true, false, null, false)[0];
  const user = selectedUser && users && model.findMatches(`^  ${selectedUser}:\\s*$`, false, true, false, null, false).find((match) => match.range.startLineNumber > users.range.endLineNumber);
  if (!user) {
    notice("This user must use the expanded YAML form before its token can be rotated.", true);
    return;
  }
  for (let line = user.range.endLineNumber + 1; line <= model.getLineCount(); line += 1) {
    const content = model.getLineContent(line);
    if (/^\S|^  [A-Za-z0-9_.-]+:\s*$/.test(content)) break;
    if (/^    token_hash:\s*/.test(content)) {
      const token = randomToken();
      const tokenHash = await sha256(token);
      editor.executeEdits("rotate-user-token", [{ range: new monaco.Range(line, 1, line, model.getLineMaxColumn(line)), text: `    token_hash: ${tokenHash}` }]);
      openMcpConfiguration(selectedUser, token);
      renderMcpUsers();
      return;
    }
  }
  notice("This user has no token_hash to rotate.", true);
}

async function copyMcpConfiguration() {
  const value = $("#mcp-config").value;
  try {
    await navigator.clipboard.writeText(value);
    notice("MCP configuration copied.");
  } catch {
    const field = $("#mcp-config");
    field.focus();
    field.select();
    notice("Select and copy the configuration manually.");
  }
}

window.require.config({ paths: { vs: "./vs" } });
window.require(["vs/editor/editor.main"], () => {
  editor = monaco.editor.create($("#editor"), {
    language: "yaml", theme: "vs-dark", value: "", automaticLayout: true,
    minimap: { enabled: false }, fontSize: 14, lineHeight: 22, padding: { top: 18, bottom: 18 },
  });
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => saveConfiguration());
  refresh().catch((error) => notice(error.message, true));
});

async function saveConfiguration() {
  setBusy($("#save"), true);
  try { notice((await request("./api/config", { method: "PUT", body: JSON.stringify({ config: editor.getValue() }) })).message); }
  catch (error) { notice(error.message, true); }
  finally { setBusy($("#save"), false); }
}

$("#save").addEventListener("click", saveConfiguration);

$("#skip-onboarding").addEventListener("click", configureManually);

$("#add-user").addEventListener("click", () => $("#user-dialog").showModal());
$("#new-user-form").addEventListener("submit", insertUser);
$("#copy-mcp-config").addEventListener("click", copyMcpConfiguration);
$("#rotate-user-token").addEventListener("click", rotateSelectedUserToken);

$("#check-config").addEventListener("click", async () => {
  const button = $("#check-config");
  setBusy(button, true);
  try { notice((await request("./api/config/check", { method: "POST", body: JSON.stringify({ config: editor.getValue() }) })).message); }
  catch (error) { notice(error.message, true); }
  finally { setBusy(button, false); }
});

$("#policy-check").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  if (!form.reportValidity()) return;
  const button = form.querySelector("button");
  setBusy(button, true);
  try {
    const data = new FormData(form);
    notice((await request("./api/policy-check", { method: "POST", body: JSON.stringify({ config: editor.getValue(), user: data.get("user"), folder: data.get("folder") }) })).message);
  } catch (error) { notice(error.message, true); }
  finally { setBusy(button, false); }
});

$("#save-network").addEventListener("click", async () => {
  try {
    notice((await request("./api/settings", { method: "POST", body: JSON.stringify({ lan_tls_enabled: $("#lan-tls").checked, tls_certificate: $("#certificate").value, tls_key: $("#key").value }) })).message);
  } catch (error) { notice(error.message, true); }
});
