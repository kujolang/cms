#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import { join, resolve } from "node:path";
import process from "node:process";

const options = new Map(process.argv.slice(2).map((arg) => {
  const [key, ...value] = arg.split("=");
  return [key.replace(/^--/, ""), value.join("=")];
}));
const roots = {
  baseline: resolve(options.get("baseline-dir") || ""),
  current: resolve(options.get("current-dir") || ""),
};
const outputDir = resolve(options.get("output-dir") || "benchmarks/hardening/raw/paired");
const kujoBin = resolve(options.get("kujo-bin") || process.env.KUJO_BIN || `${process.env.HOME}/.local/bin/kujo`);
const blocks = Number(options.get("blocks") || 5);
const requestsPerTrial = Number(options.get("requests-per-trial") || 5);
mkdirSync(outputDir, { recursive: true });

const sleep = (ms) => new Promise((resolvePromise) => setTimeout(resolvePromise, ms));

function run(commandName, args, settings = {}) {
  return spawnSync(commandName, args, { encoding: "utf8", cwd: settings.cwd, input: settings.input, timeout: 120_000 });
}

function request(port, path) {
  return new Promise((resolvePromise, rejectPromise) => {
    const started = process.hrtime.bigint();
    const req = http.request({ host: "127.0.0.1", port, path, agent: false }, (response) => {
      response.resume();
      response.on("end", () => resolvePromise({
        status: response.statusCode,
        latency_ms: Number(process.hrtime.bigint() - started) / 1e6,
      }));
    });
    req.on("error", rejectPromise);
    req.end();
  });
}

async function waitForHealth(port, child) {
  const started = process.hrtime.bigint();
  for (;;) {
    if (child.exitCode !== null) throw new Error(`server exited: ${child.exitCode}`);
    try {
      const response = await request(port, "/health");
      if (response.status === 200) return Number(process.hrtime.bigint() - started) / 1e6;
    } catch {}
    if (Number(process.hrtime.bigint() - started) / 1e6 > 15_000) throw new Error("startup timeout");
    await sleep(10);
  }
}

function start(label, port, dbPath) {
  return spawn(kujoBin, ["run", "--interpreter", "backend/runtime/main.kujo"], {
    cwd: roots[label],
    env: {
      ...process.env,
      CMS_ENV: "development",
      CMS_API_HOST: "127.0.0.1",
      CMS_API_PORT: String(port),
      CMS_SITE_URL: `http://127.0.0.1:${port}`,
      CMS_DB_PATH: dbPath,
      CMS_API_TOKEN: "hardening-benchmark-token-1234567890-Aa",
      CMS_AUDIT_LOG: "false",
      CMS_STRUCTURED_LOGS: "false",
      CMS_RATE_MAX_REQUESTS: "1000000",
    },
    stdio: "ignore",
  });
}

async function stop(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([new Promise((resolvePromise) => child.once("exit", resolvePromise)), sleep(2_000)]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

async function prepare(label, port) {
  const template = join(outputDir, `${label}-template.db`);
  rmSync(template, { force: true });
  rmSync(`${template}-wal`, { force: true });
  rmSync(`${template}-shm`, { force: true });
  const child = start(label, port, template);
  await waitForHealth(port, child);
  await stop(child);
  const sql = `
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO content_types (type_key,label,singular_label,description,supports_json,is_system,created_at,updated_at)
VALUES ('article','Articles','Article','Benchmark content','{}',0,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
WITH RECURSIVE counter(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM counter WHERE x < 5000)
INSERT INTO entries (content_type_key,title,slug,status,excerpt,body,meta_json,author_id,published_at,unpublish_at,created_at,updated_at)
SELECT 'article','Benchmark entry ' || x,'entry-' || x,'published','Excerpt ' || x,printf('%.*c',512,'x'),'{}','benchmark','2026-01-01T00:00:00Z',NULL,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z' FROM counter;
COMMIT;
`;
  const seeded = run("sqlite3", [template], { input: sql });
  if (seeded.status !== 0) throw new Error(seeded.stderr);
  return template;
}

const templates = {
  baseline: await prepare("baseline", 52690),
  current: await prepare("current", 52691),
};
const samples = { baseline: [], current: [] };
let trialNumber = 0;
for (let block = 0; block < blocks; block += 1) {
  const sequence = block % 2 === 0 ? ["baseline", "current", "current", "baseline"] : ["current", "baseline", "baseline", "current"];
  for (const label of sequence) {
    trialNumber += 1;
    const port = 52700 + trialNumber;
    const dbPath = join(outputDir, `${label}-trial-${trialNumber}.db`);
    copyFileSync(templates[label], dbPath);
    const child = start(label, port, dbPath);
    const startupMs = await waitForHealth(port, child);
    for (let index = 0; index < 3; index += 1) {
      await request(port, "/health");
      await request(port, "/v1/entries?limit=25&offset=0");
    }
    const health = [];
    const entries = [];
    for (let index = 0; index < requestsPerTrial; index += 1) {
      health.push((await request(port, "/health")).latency_ms);
      entries.push((await request(port, "/v1/entries?limit=25&offset=0")).latency_ms);
    }
    samples[label].push({ block, trial_number: trialNumber, startup_ms: startupMs, health_ms: health, entries_ms: entries });
    await stop(child);
    rmSync(dbPath, { force: true });
    rmSync(`${dbPath}-wal`, { force: true });
    rmSync(`${dbPath}-shm`, { force: true });
  }
}

const result = {
  generated_at: new Date().toISOString(),
  design: "Counterbalanced ABBA blocks; identical 5,000-entry databases; three endpoint warmups per trial.",
  blocks,
  trials_per_version: blocks * 2,
  requests_per_trial: requestsPerTrial,
  baseline_sha: run("git", ["rev-parse", "HEAD"], { cwd: roots.baseline }).stdout.trim(),
  current_sha: run("git", ["rev-parse", "HEAD"], { cwd: roots.current }).stdout.trim(),
  samples,
};
writeFileSync(join(outputDir, "paired-results.json"), `${JSON.stringify(result, null, 2)}\n`);
console.log(JSON.stringify({ output: join(outputDir, "paired-results.json"), trials_per_version: blocks * 2 }, null, 2));
