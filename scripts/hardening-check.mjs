#!/usr/bin/env node

import { readFileSync } from "node:fs";

const [label, indexText] = process.argv.slice(2);
const results = JSON.parse(readFileSync("benchmarks/hardening/evaluation-results.json", "utf8"));
const entries = Object.entries(results.eval.criteria[label] || {});
const index = Number(indexText);
if (!Number.isInteger(index) || index < 0 || index >= entries.length) {
  console.error(`Unknown check: ${label}.${indexText}`);
  process.exit(2);
}
const [criterion, passed] = entries[index];
console.log(JSON.stringify({ label, criterion, passed }));
process.exit(passed === true ? 0 : 1);
