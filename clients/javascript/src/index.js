export class KujoCmsError extends Error {
  constructor(message, { status = 0, code = "request_failed", details = {} } = {}) {
    super(message); this.name = "KujoCmsError"; this.status = status; this.code = code; this.details = details;
  }
}

export class KujoCmsClient {
  constructor({ baseUrl, token = "", session = "", fetchImpl = globalThis.fetch } = {}) {
    if (!baseUrl || typeof fetchImpl !== "function") throw new TypeError("baseUrl and fetchImpl are required");
    this.baseUrl = String(baseUrl).replace(/\/+$/, ""); this.token = token; this.session = session; this.fetchImpl = fetchImpl;
  }
  withAuth({ token = this.token, session = this.session } = {}) { return new KujoCmsClient({ baseUrl: this.baseUrl, token, session, fetchImpl: this.fetchImpl }); }
  async request(method, path, body) {
    const headers = { Accept: "application/json" };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    if (this.session) headers["X-CMS-Session"] = this.session;
    const options = { method, headers };
    if (body !== undefined) { headers["Content-Type"] = "application/json"; options.body = JSON.stringify(body); }
    const response = await this.fetchImpl(`${this.baseUrl}${path}`, options);
    const text = await response.text(); let payload = null;
    if (text) { try { payload = JSON.parse(text); } catch { throw new KujoCmsError("CMS returned invalid JSON", { status: response.status, code: "invalid_response" }); } }
    if (!response.ok || payload?.ok === false) { const error = payload?.error ?? {}; throw new KujoCmsError(error.message || `CMS request failed with HTTP ${response.status}`, { status: response.status, code: error.code, details: error.details }); }
    return payload?.data ?? payload;
  }
  createSession(input) { return this.request("POST", "/v1/auth/sessions", input); }
  exchangeProvider(input) { return this.request("POST", "/v1/auth/providers/exchange", input); }
  me() { return this.request("GET", "/v1/auth/me"); }
  revokeSession() { return this.request("DELETE", "/v1/auth/session"); }
  listEntries(query = {}) { return this.request("GET", `/v1/entries?${new URLSearchParams(query)}`); }
  getEntry(id) { return this.request("GET", `/v1/entries/${encodeURIComponent(id)}`); }
  createEntry(entry, termIds = []) { return this.request("POST", "/v1/entries", { ...entry, term_ids: termIds }); }
  composeEntry(id, workflow) { return this.request("PATCH", `/v1/entries/${encodeURIComponent(id)}/compose`, workflow); }
  bulkTerms(taxonomyId, terms) { return this.request("POST", `/v1/taxonomies/${encodeURIComponent(taxonomyId)}/terms/bulk`, { terms }); }
  ingestMedia(filename, altText = "") { return this.request("POST", "/v1/media/ingest", { filename, alt_text: altText }); }
  uploadMedia(filename, dataBase64, altText = "") { return this.request("POST", "/v1/media/upload", { filename, data_base64: dataBase64, alt_text: altText }); }
  mediaFile(objectKey) { return this.request("GET", `/v1/media/files/${encodeURIComponent(objectKey)}`); }
  registerExternalMedia(input) { return this.request("POST", "/v1/media/register-external", input); }
  seoInventory(query = {}) { return this.request("GET", `/v1/seo/entries?${new URLSearchParams(query)}`); }
  updateEntrySeo(id, changes) { return this.request("PATCH", `/v1/entries/${encodeURIComponent(id)}/seo`, changes); }
  bulkUpdateSeo(entryIds, changes) { return this.request("POST", "/v1/seo/entries/bulk", { entry_ids: entryIds, changes }); }
  socialSharing() { return this.request("GET", "/v1/settings/social-sharing"); }
  updateSocialSharing(settings) { return this.request("PATCH", "/v1/settings/social-sharing", settings); }
  extensionCatalog() { return this.request("GET", "/v1/extensions/catalog"); }
  extensionNavigation() { return this.request("GET", "/v1/extensions/navigation"); }
  ingestExtension(filename, activate = false) { return this.request("POST", "/v1/extensions/packages/ingest", { filename, activate }); }
  uploadExtension(dataBase64, activate = false) { return this.request("POST", "/v1/extensions/packages/upload", { data_base64: dataBase64, activate }); }
  abilities(category = "") { return this.request("GET", `/v1/abilities${category ? `?category=${encodeURIComponent(category)}` : ""}`); }
  runAbility(name, input = {}) { const [namespace, ability] = String(name).split("/"); return this.request("POST", `/v1/abilities/${encodeURIComponent(namespace)}/${encodeURIComponent(ability)}/run`, { input }); }
  setAbility(name, enabled) { const [namespace, ability] = String(name).split("/"); return this.request("PATCH", `/v1/abilities/${encodeURIComponent(namespace)}/${encodeURIComponent(ability)}`, { enabled }); }
  connectors() { return this.request("GET", "/v1/ai/connectors"); }
  setConnector(key, enabled) { return this.request("PATCH", `/v1/ai/connectors/${encodeURIComponent(key)}`, { enabled }); }
  connectorHealth(key) { return this.request("POST", `/v1/ai/connectors/${encodeURIComponent(key)}/health`, {}); }
  mcpTools() { return this.request("GET", "/v1/ai/mcp/tools"); }
  webMcpManifest() { return this.request("GET", "/v1/webmcp"); }
}

export function buildShareUrl(network, { url, title = "", text = "", account = "", media = "" } = {}) {
  const target = String(url || ""); if (!target) throw new TypeError("url is required");
  const shareText = text || title; const cleanAccount = String(account).replace(/^@+/, ""); const query = (base, values) => `${base}?${new URLSearchParams(Object.entries(values).filter(([, value]) => value))}`;
  if (network === "x") return query("https://x.com/intent/post", { url: target, text: shareText, via: cleanAccount });
  if (network === "bluesky") return query("https://bsky.app/intent/compose", { text: [shareText, target, cleanAccount ? `@${cleanAccount}` : ""].filter(Boolean).join(" ") });
  if (network === "linkedin") return query("https://www.linkedin.com/sharing/share-offsite/", { url: target });
  if (network === "facebook") return query("https://www.facebook.com/sharer/sharer.php", { u: target });
  if (network === "reddit") return query("https://www.reddit.com/submit", { url: target, title });
  if (network === "whatsapp") return query("https://wa.me/", { text: [shareText, target].filter(Boolean).join(" ") });
  if (network === "pinterest") return query("https://www.pinterest.com/pin/create/button/", { url: target, description: shareText, media });
  if (network === "email") return query("mailto:", { subject: title, body: [text, target].filter(Boolean).join("\n\n") });
  throw new TypeError(`Unsupported sharing network: ${network}`);
}

export function resolveAdminNavigation(coreItems = [], extensionItems = [], capabilities = []) {
  const allowed = new Set(capabilities); const byKey = new Map(coreItems.map((item) => [item.key, { ...item }]));
  for (const item of extensionItems) {
    if (item.capability && !allowed.has("*") && !allowed.has(item.capability)) continue;
    if (byKey.has(item.key)) byKey.set(item.key, { ...byKey.get(item.key), order: item.order }); else byKey.set(item.key, { ...item });
  }
  return [...byKey.values()].filter((item) => !item.capability || allowed.has("*") || allowed.has(item.capability)).sort((a, b) => (a.order ?? 500) - (b.order ?? 500) || String(a.label).localeCompare(String(b.label)));
}
