#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const runtimePath = process.argv[2];
if (!runtimePath) throw new Error('usage: test-webmcp-runtime.js <runtime>');
const source = fs.readFileSync(runtimePath, 'utf8');

async function load(supported = true) {
  const tools = [];
  const requests = [];
  const context = {
    AbortController, AbortSignal, URL, Error, Promise, Array, Object, String, Number, JSON,
    location: {origin: 'https://example.test', href: 'https://example.test/'},
    addEventListener() {},
    fetch: async (url, options) => {
      requests.push({url, options});
      const path = new URL(url).pathname;
      const data = path.endsWith('/site') ? {schema: 'kujo-cms-webmcp/v1'}
        : path.endsWith('/search') ? {results: [{id: 'article:hello'}]}
        : path.endsWith('/content') ? {items: [{id: 'article:hello'}]}
        : {id: 'article:hello', summary: 'Hello'};
      return {ok: true, json: async () => ({ok: true, data})};
    },
    document: {
      modelContext: supported ? {registerTool: async tool => tools.push(tool)} : undefined,
      currentScript: {dataset: {kujoWebmcpApi: '/v1/webmcp/'}},
      baseURI: 'https://example.test/'
    }
  };
  vm.runInNewContext(source, context, {filename: runtimePath});
  await new Promise(resolve => setImmediate(resolve));
  return {tools, requests};
}

(async () => {
  assert.equal((await load(false)).tools.length, 0);
  const loaded = await load();
  assert.deepEqual(loaded.tools.map(tool => tool.name), ['get_site_info', 'search_site', 'list_content', 'get_content']);
  for (const tool of loaded.tools) {
    assert.equal(tool.annotations.readOnlyHint, true);
    assert.equal(tool.annotations.untrustedContentHint, true);
    assert.equal(tool.inputSchema.additionalProperties, false);
  }
  const tools = Object.fromEntries(loaded.tools.map(tool => [tool.name, tool]));
  assert.equal((await tools.get_site_info.execute({})).schema, 'kujo-cms-webmcp/v1');
  assert.equal((await tools.search_site.execute({query: 'hello'})).results[0].id, 'article:hello');
  assert.equal((await tools.list_content.execute({type: 'article'})).items[0].id, 'article:hello');
  assert.equal((await tools.get_content.execute({id: 'article:hello'})).id, 'article:hello');
  assert.ok(loaded.requests.every(request => new URL(request.url).origin === 'https://example.test'));
  await assert.rejects(() => tools.search_site.execute({query: 'x', surprise: true}), /unknown argument/);
  await assert.rejects(() => tools.get_content.execute({id: 'x', url: '/x'}), /exactly one/);
  await assert.rejects(() => tools.get_content.execute({url: 'https://evil.test/x'}), /same-origin/);
  console.log('WebMCP browser runtime tests passed');
})().catch(error => { console.error(error); process.exit(1); });
