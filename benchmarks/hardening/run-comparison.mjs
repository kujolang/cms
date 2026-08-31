#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import { basename, join, resolve } from "node:path";
import process from "node:process";

const args = new Map();
for (const arg of process.argv.slice(2)) {
  const [key, ...rest] = arg.split("=");
  args.set(key.replace(/^--/, ""), rest.join("="));
}

const baselineDir = resolve(args.get("baseline-dir") || "");
const currentDir = resolve(args.get("current-dir") || process.cwd());
const outputDir = resolve(args.get("output-dir") || join(process.cwd(), "benchmarks/hardening/raw"));
const kujoBin = resolve(args.get("kujo-bin") || process.env.KUJO_BIN || `${process.env.HOME}/.local/bin/kujo`);
const runs = Number(args.get("runs") || 20);
const warmups = Number(args.get("warmups") || 3);
const startupRuns = Number(args.get("startup-runs") || 10);
const startupWarmups = Number(args.get("startup-warmups") || 3);
const throughputRequests = Number(args.get("throughput-requests") || 50);
const order = args.get("order") || "baseline-first";

if (!baselineDir || baselineDir === "/") {
  throw new Error("--baseline-dir is required");
}

mkdirSync(outputDir, { recursive: true });

const sleep = (ms) => new Promise((resolvePromise) => setTimeout(resolvePromise, ms));

function command(commandName, commandArgs, options = {}) {
  const result = spawnSync(commandName, commandArgs, {
    cwd: options.cwd,
    env: options.env || process.env,
    encoding: "utf8",
    input: options.input,
    timeout: options.timeout || 120_000,
  });
  return {
    command: [commandName, ...commandArgs].join(" "),
    status: result.status,
    signal: result.signal,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    duration_ms: null,
    error: result.error ? String(result.error) : null,
  };
}

function git(cwd, ...gitArgs) {
  const result = command("git", gitArgs, { cwd });
  if (result.status !== 0) throw new Error(result.stderr);
  return result.stdout.trim();
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  const index = Math.max(0, Math.ceil(sorted.length * fraction) - 1);
  return sorted[Math.min(index, sorted.length - 1)];
}

function summarize(values) {
  const nums = values.filter(Number.isFinite);
  if (nums.length === 0) return { n: 0, min: null, max: null, mean: null, median: null, p95: null, p99: null, stddev: null };
  const sorted = [...nums].sort((a, b) => a - b);
  const mean = nums.reduce((sum, value) => sum + value, 0) / nums.length;
  const variance = nums.reduce((sum, value) => sum + ((value - mean) ** 2), 0) / nums.length;
  const midpoint = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2;
  return {
    n: nums.length,
    min: sorted[0],
    max: sorted.at(-1),
    mean,
    median,
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    stddev: Math.sqrt(variance),
  };
}

function parseCpuTime(text) {
  const value = text.trim();
  if (!value) return null;
  const parts = value.split(":").map(Number);
  if (parts.some(Number.isNaN)) return null;
  if (parts.length === 3) return ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
  return ((parts[0] * 60) + parts[1]) * 1000;
}

function processStats(pid) {
  const result = spawnSync("ps", ["-o", "rss=,time=", "-p", String(pid)], { encoding: "utf8" });
  const match = (result.stdout || "").trim().match(/^(\d+)\s+(.+)$/);
  if (!match) return { rss_kb: null, cpu_ms: null };
  return { rss_kb: Number(match[1]), cpu_ms: parseCpuTime(match[2]) };
}

function requestOnce({ port, path, method = "GET", body = "", token = "", agent }) {
  return new Promise((resolvePromise, rejectPromise) => {
    const started = process.hrtime.bigint();
    const headers = {};
    if (body) {
      headers["Content-Type"] = "application/json";
      headers["Content-Length"] = Buffer.byteLength(body);
    }
    if (token) headers.Authorization = `Bearer ${token}`;
    const request = http.request({ host: "127.0.0.1", port, path, method, headers, agent }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
        const responseBody = Buffer.concat(chunks);
        resolvePromise({
          latency_ms: elapsed,
          status: response.statusCode,
          bytes: responseBody.length,
          body: responseBody.toString("utf8"),
        });
      });
    });
    request.on("error", rejectPromise);
    if (body) request.write(body);
    request.end();
  });
}

async function waitForHealth(port, child, timeoutMs = 15_000) {
  const started = process.hrtime.bigint();
  while ((Number(process.hrtime.bigint() - started) / 1e6) < timeoutMs) {
    if (child.exitCode !== null) throw new Error(`server exited with ${child.exitCode}`);
    try {
      const response = await requestOnce({ port, path: "/health", agent: false });
      if (response.status === 200) return Number(process.hrtime.bigint() - started) / 1e6;
    } catch {}
    await sleep(10);
  }
  throw new Error("server did not become healthy");
}

async function stopServer(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolvePromise) => child.once("exit", resolvePromise)),
    sleep(2_000),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

function startServer(repoDir, port, dbPath, suffix = "") {
  const logPath = join(outputDir, `${basename(repoDir)}-${port}${suffix}.server.log`);
  const logChunks = [];
  const child = spawn(kujoBin, ["run", "--interpreter", "backend/runtime/main.kujo"], {
    cwd: repoDir,
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
      CMS_RATE_LIMIT_MODE: "memory",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => logChunks.push(chunk));
  child.stderr.on("data", (chunk) => logChunks.push(chunk));
  child.once("exit", () => writeFileSync(logPath, Buffer.concat(logChunks)));
  return child;
}

async function measureRequestSeries(port, definition, count = runs, warmupCount = warmups) {
  const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
  for (let index = 0; index < warmupCount; index += 1) {
    await requestOnce({ port, agent, ...definition });
  }
  const samples = [];
  for (let index = 0; index < count; index += 1) {
    samples.push(await requestOnce({ port, agent, ...definition }));
  }
  agent.destroy();
  return {
    name: definition.name,
    path: definition.path,
    method: definition.method || "GET",
    expected_status: definition.expectedStatus,
    statuses: Object.fromEntries([...new Set(samples.map((sample) => sample.status))].map((status) => [status, samples.filter((sample) => sample.status === status).length])),
    latency_ms: summarize(samples.map((sample) => sample.latency_ms)),
    response_bytes: summarize(samples.map((sample) => sample.bytes)),
    sample_body: samples[0]?.body.slice(0, 2_000) || "",
  };
}

async function measureThroughput(port, path, total = 200, concurrency = 10) {
  const agent = new http.Agent({ keepAlive: true, maxSockets: concurrency });
  const latencies = [];
  const statuses = [];
  let cursor = 0;
  const started = process.hrtime.bigint();
  const worker = async () => {
    while (cursor < total) {
      cursor += 1;
      const response = await requestOnce({ port, path, agent });
      latencies.push(response.latency_ms);
      statuses.push(response.status);
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));
  const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
  agent.destroy();
  return {
    path,
    total,
    concurrency,
    duration_ms: durationMs,
    requests_per_second: total / (durationMs / 1_000),
    statuses: Object.fromEntries([...new Set(statuses)].map((status) => [status, statuses.filter((value) => value === status).length])),
    latency_ms: summarize(latencies),
  };
}

function insertEntries(dbPath, from, to) {
  if (to < from) return;
  const sql = `
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO content_types (type_key,label,singular_label,description,supports_json,is_system,created_at,updated_at)
VALUES ('article','Articles','Article','Benchmark content','{}',0,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
WITH RECURSIVE counter(x) AS (SELECT ${from} UNION ALL SELECT x + 1 FROM counter WHERE x < ${to})
INSERT INTO entries (content_type_key,title,slug,status,excerpt,body,meta_json,author_id,published_at,unpublish_at,created_at,updated_at)
SELECT 'article','Benchmark entry ' || x,'entry-' || x,'published','Excerpt ' || x,
       printf('%.*c', 512, 'x'),'{}','benchmark','2026-01-01T00:00:00Z',NULL,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'
FROM counter;
COMMIT;
`;
  const result = command("sqlite3", [dbPath], { input: sql });
  if (result.status !== 0) throw new Error(`seed failed: ${result.stderr}`);
}

function insertPrivateDraft(dbPath) {
  const sql = `
INSERT INTO entries (content_type_key,title,slug,status,excerpt,body,meta_json,author_id,published_at,unpublish_at,created_at,updated_at)
VALUES ('article','Private draft','private-draft','draft','private','sensitive draft evidence','{}','benchmark',NULL,NULL,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
`;
  const result = command("sqlite3", [dbPath], { input: sql });
  if (result.status !== 0) throw new Error(`draft seed failed: ${result.stderr}`);
}

async function productionSafetyProbe(repoDir, port, label) {
  const dbPath = join(outputDir, `${label}-production.db`);
  rmSync(dbPath, { force: true });
  const started = process.hrtime.bigint();
  const child = spawn(kujoBin, ["run", "--interpreter", "backend/runtime/main.kujo"], {
    cwd: repoDir,
    env: {
      ...process.env,
      CMS_ENV: "production",
      CMS_API_HOST: "127.0.0.1",
      CMS_API_PORT: String(port),
      CMS_SITE_URL: `http://127.0.0.1:${port}`,
      CMS_DB_PATH: dbPath,
      CMS_API_TOKEN: "production-safety-probe-token-123-Aa",
      CMS_TRUSTED_INGRESS_LIMITS: "false",
      CMS_RATE_LIMIT_MODE: "memory",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const chunks = [];
  child.stdout.on("data", (chunk) => chunks.push(chunk));
  child.stderr.on("data", (chunk) => chunks.push(chunk));
  let outcome = "timeout";
  await Promise.race([
    new Promise((resolvePromise) => child.once("exit", () => { outcome = "exited"; resolvePromise(); })),
    (async () => {
      try {
        await waitForHealth(port, child, 3_000);
        outcome = "became_healthy";
      } catch {
        if (child.exitCode !== null) outcome = "exited";
      }
    })(),
    sleep(3_100),
  ]);
  const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
  const exitCode = child.exitCode;
  await stopServer(child);
  return { outcome, elapsed_ms: elapsed, exit_code: exitCode, output: Buffer.concat(chunks).toString("utf8").slice(0, 4_000) };
}

async function benchmarkVersion(label, repoDir, portBase) {
  const metadata = {
    label,
    repo_dir: repoDir,
    branch: git(repoDir, "branch", "--show-current"),
    sha: git(repoDir, "rev-parse", "HEAD"),
    commit_timestamp: git(repoDir, "show", "-s", "--format=%cI", "HEAD"),
    tags: git(repoDir, "tag", "--points-at", "HEAD").split("\n").filter(Boolean),
    worktree_status: git(repoDir, "status", "--porcelain"),
  };

  const startupSamples = [];
  for (let trial = 0; trial < startupWarmups + startupRuns; trial += 1) {
    const dbPath = join(outputDir, `${label}-startup-${trial}.db`);
    rmSync(dbPath, { force: true });
    rmSync(`${dbPath}-wal`, { force: true });
    rmSync(`${dbPath}-shm`, { force: true });
    const child = startServer(repoDir, portBase + trial, dbPath, "-startup");
    const startupMs = await waitForHealth(portBase + trial, child);
    const stats = processStats(child.pid);
    await stopServer(child);
    if (trial >= startupWarmups) startupSamples.push({ startup_ms: startupMs, rss_kb: stats.rss_kb });
  }

  const port = portBase + 50;
  const dbPath = join(outputDir, `${label}-workload.db`);
  rmSync(dbPath, { force: true });
  rmSync(`${dbPath}-wal`, { force: true });
  rmSync(`${dbPath}-shm`, { force: true });
  const server = startServer(repoDir, port, dbPath, "-workload");
  await waitForHealth(port, server);
  let peakRssKb = processStats(server.pid).rss_kb || 0;
  const memoryTimer = setInterval(() => {
    peakRssKb = Math.max(peakRssKb, processStats(server.pid).rss_kb || 0);
  }, 500);

  const scaling = [];
  let seeded = 0;
  for (const size of [0, 10, 100, 1_000, 5_000]) {
    if (size > seeded) {
      insertEntries(dbPath, seeded + 1, size);
      seeded = size;
    }
    scaling.push({
      entries: size,
      result: await measureRequestSeries(port, {
        name: `entries-${size}`,
        path: `/v1/entries?limit=100&offset=${Math.max(0, size - 100)}&sort_by=id&sort_dir=asc`,
        expectedStatus: 200,
      }),
    });
  }
  insertPrivateDraft(dbPath);

  const workloads = [];
  for (const definition of [
    { name: "minimal-health", path: "/health", expectedStatus: 200 },
    { name: "typical-entries", path: "/v1/entries?limit=25&offset=0", expectedStatus: 200 },
    { name: "large-entries", path: "/v1/entries?limit=100&offset=4900&sort_by=id&sort_dir=asc", expectedStatus: 200 },
    { name: "failure-invalid-cursor", path: "/v1/entries?cursor=not-a-number", expectedStatus: 400 },
    { name: "failure-unauthorized-write", path: "/v1/content-types", method: "POST", body: "{}", expectedStatus: 401 },
    { name: "failure-invalid-json", path: "/v1/content-types", method: "POST", body: "{", token: "hardening-benchmark-token-1234567890-Aa", expectedStatus: 400 },
    { name: "failure-missing-entry", path: "/v1/entries/999999", expectedStatus: 404 },
    { name: "privacy-anonymous-draft", path: "/v1/entries/by-slug/article/private-draft", expectedStatus: 404 },
  ]) {
    workloads.push(await measureRequestSeries(port, definition));
  }

  const throughput = [];
  for (const concurrency of [1, 10, 25]) {
    throughput.push(await measureThroughput(port, "/v1/entries?limit=25&offset=0", throughputRequests, concurrency));
  }

  const agentOutputs = [];
  for (const definition of [
    { name: "capabilities", path: "/v1", required: "/v1/entries" },
    { name: "openapi", path: "/v1/openapi.json", required: "3.1.0" },
    { name: "llms", path: "/llms.txt", required: "/v1/entries" },
  ]) {
    const response = await requestOnce({ port, path: definition.path, agent: false });
    agentOutputs.push({
      name: definition.name,
      path: definition.path,
      status: response.status,
      bytes: response.bytes,
      lines: response.body.split(/\r?\n/).length,
      words: response.body.trim() ? response.body.trim().split(/\s+/).length : 0,
      required_evidence_present: response.body.includes(definition.required),
      sha256: command("shasum", ["-a", "256"], { input: response.body }).stdout.split(/\s+/)[0],
    });
    writeFileSync(join(outputDir, `${label}-${definition.name}.txt`), response.body);
  }

  clearInterval(memoryTimer);
  const endingStats = processStats(server.pid);
  await stopServer(server);
  const dbBytes = Number(command("stat", ["-f", "%z", dbPath]).stdout.trim());
  const productionSafety = await productionSafetyProbe(repoDir, portBase + 90, label);

  const testStarted = process.hrtime.bigint();
  const nativeTests = command(kujoBin, ["test-run", "tests/cms_contract_tests.kujo"], { cwd: repoDir, timeout: 300_000 });
  nativeTests.duration_ms = Number(process.hrtime.bigint() - testStarted) / 1e6;
  nativeTests.output_bytes = Buffer.byteLength(nativeTests.stdout) + Buffer.byteLength(nativeTests.stderr);

  return {
    metadata,
    parameters: { runs, warmups, startup_runs: startupRuns, startup_warmups: startupWarmups, throughput_requests: throughputRequests },
    startup: {
      latency_ms: summarize(startupSamples.map((sample) => sample.startup_ms)),
      rss_kb: summarize(startupSamples.map((sample) => sample.rss_kb)),
      raw: startupSamples,
    },
    scaling,
    workloads,
    throughput,
    agent_outputs: agentOutputs,
    process: { peak_rss_kb: peakRssKb, cpu_ms_before_shutdown: endingStats.cpu_ms, database_bytes: dbBytes },
    production_safety: productionSafety,
    native_tests: nativeTests,
  };
}

const environment = {
  generated_at: new Date().toISOString(),
  hostname: command("hostname", []).stdout.trim(),
  os: command("sw_vers", []).stdout.trim().replace(/\n/g, "; "),
  kernel: command("uname", ["-a"]).stdout.trim(),
  cpu: command("sysctl", ["-n", "machdep.cpu.brand_string"]).stdout.trim(),
  logical_cores: Number(command("sysctl", ["-n", "hw.ncpu"]).stdout.trim()),
  memory_bytes: Number(command("sysctl", ["-n", "hw.memsize"]).stdout.trim()),
  kujo_version: command(kujoBin, ["--version"]).stdout.trim(),
  node_version: process.version,
  filesystem: command("df", ["-T", currentDir]).stdout.trim(),
  kujo_bin: kujoBin,
};

let baseline;
let current;
if (order === "current-first") {
  current = await benchmarkVersion("current", currentDir, 52300);
  writeFileSync(join(outputDir, "current.json"), `${JSON.stringify({ environment, ...current }, null, 2)}\n`);
  baseline = await benchmarkVersion("baseline", baselineDir, 52100);
  writeFileSync(join(outputDir, "baseline.json"), `${JSON.stringify({ environment, ...baseline }, null, 2)}\n`);
} else {
  baseline = await benchmarkVersion("baseline", baselineDir, 52100);
  writeFileSync(join(outputDir, "baseline.json"), `${JSON.stringify({ environment, ...baseline }, null, 2)}\n`);
  current = await benchmarkVersion("current", currentDir, 52300);
  writeFileSync(join(outputDir, "current.json"), `${JSON.stringify({ environment, ...current }, null, 2)}\n`);
}

writeFileSync(join(outputDir, "comparison-input.json"), `${JSON.stringify({ environment, baseline, current }, null, 2)}\n`);
console.log(JSON.stringify({ baseline: baseline.metadata.sha, current: current.metadata.sha, output_dir: outputDir }, null, 2));
