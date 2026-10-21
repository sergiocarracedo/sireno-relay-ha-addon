let editor;
const $ = (selector) => document.querySelector(selector);

function notice(message, error = false) {
  const target = $("#message");
  target.textContent = message;
  target.classList.toggle("error", error);
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
  $("#state").textContent = "Protected";
  $("#state").classList.add("ready");
  editor.setValue(status.config);
  $("#lan-tls").checked = status.settings.lan_tls_enabled;
  $("#certificate").value = status.settings.tls_certificate;
  $("#key").value = status.settings.tls_key;
}

async function refresh() {
  const status = await request("./api/status");
  if (status.configured) showEditor(status);
  else {
    $("#onboarding").hidden = false;
    $("#state").textContent = "Setup required";
    setTimeout(refresh, 3000);
  }
}

window.require.config({ paths: { vs: "./vs" } });
window.require(["vs/editor/editor.main"], () => {
  editor = monaco.editor.create($("#editor"), {
    language: "yaml", theme: "vs-dark", value: "", automaticLayout: true,
    minimap: { enabled: false }, fontSize: 14, lineHeight: 22, padding: { top: 18, bottom: 18 },
  });
  refresh().catch((error) => notice(error.message, true));
});

$("#save").addEventListener("click", async () => {
  $("#save").disabled = true;
  try { notice((await request("./api/config", { method: "PUT", body: JSON.stringify({ config: editor.getValue() }) })).message); }
  catch (error) { notice(error.message, true); }
  finally { $("#save").disabled = false; }
});

$("#save-network").addEventListener("click", async () => {
  try {
    notice((await request("./api/settings", { method: "POST", body: JSON.stringify({ lan_tls_enabled: $("#lan-tls").checked, tls_certificate: $("#certificate").value, tls_key: $("#key").value }) })).message);
  } catch (error) { notice(error.message, true); }
});
