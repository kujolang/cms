import test from "node:test";
import assert from "node:assert/strict";
import { KujoCmsClient, buildShareUrl, resolveAdminNavigation } from "../src/index.js";

test("client parses empty success bodies without JSON errors", async () => {
  const client = new KujoCmsClient({ baseUrl: "https://cms.test", fetchImpl: async () => new Response(null, { status: 204 }) });
  assert.equal(await client.request("DELETE", "/v1/auth/session"), null);
});

test("sharing helpers cover all CMS networks", () => {
  for (const network of ["x", "linkedin", "facebook", "bluesky", "reddit", "whatsapp", "email", "pinterest"]) assert.match(buildShareUrl(network, { url: "https://example.test/post", title: "Hello", account: "@example" }), /example/);
});

test("navigation helpers merge extension order and filter capabilities", () => {
  const core = [{ key: "content", label: "Content", order: 200, capability: "view_content" }];
  const extensions = [{ key: "forms", label: "Forms", order: 150, capability: "manage_extensions" }, { key: "content", order: 100, capability: "view_content" }];
  assert.deepEqual(resolveAdminNavigation(core, extensions, ["view_content"]).map((item) => item.key), ["content"]);
  assert.deepEqual(resolveAdminNavigation(core, extensions, ["*"]).map((item) => item.key), ["content", "forms"]);
});
