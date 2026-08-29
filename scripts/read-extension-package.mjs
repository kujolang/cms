#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename } from "node:path";
import { inflateRawSync } from "node:zlib";

const MAX_ARCHIVE = 16 * 1024 * 1024;
const MAX_EXPANDED = 64 * 1024 * 1024;
const MAX_FILES = 2_000;
const MAX_MANIFEST = 128 * 1024;

function fail(message) { throw new Error(message); }
function safePath(value) {
  return value && !value.startsWith("/") && !value.includes("\\") && !value.includes("\0") && !value.split("/").includes("..");
}
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function inspectZip(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65_557); offset -= 1) {
    if (view.getUint32(offset, true) === 0x06054b50) { eocd = offset; break; }
  }
  if (eocd < 0) fail("The file is not a supported ZIP archive.");
  const fileCount = view.getUint16(eocd + 10, true);
  const centralSize = view.getUint32(eocd + 12, true);
  const centralOffset = view.getUint32(eocd + 16, true);
  if (!fileCount || fileCount > MAX_FILES || centralOffset + centralSize > bytes.length) fail("The ZIP directory is invalid or exceeds the file limit.");

  const decoder = new TextDecoder();
  const entries = [];
  let expanded = 0;
  let cursor = centralOffset;
  while (cursor < centralOffset + centralSize) {
    if (view.getUint32(cursor, true) !== 0x02014b50) fail("The ZIP directory is malformed.");
    const flags = view.getUint16(cursor + 8, true);
    const method = view.getUint16(cursor + 10, true);
    const crc = view.getUint32(cursor + 16, true);
    const compressedSize = view.getUint32(cursor + 20, true);
    const uncompressedSize = view.getUint32(cursor + 24, true);
    const nameLength = view.getUint16(cursor + 28, true);
    const extraLength = view.getUint16(cursor + 30, true);
    const commentLength = view.getUint16(cursor + 32, true);
    const localOffset = view.getUint32(cursor + 42, true);
    const path = decoder.decode(bytes.subarray(cursor + 46, cursor + 46 + nameLength));
    if ((flags & 1) !== 0) fail("Encrypted ZIP packages are not supported.");
    if (![0, 8].includes(method) || !safePath(path)) fail("The ZIP contains an unsupported or unsafe entry.");
    expanded += uncompressedSize;
    if (expanded > MAX_EXPANDED) fail("The ZIP expands beyond the 64 MB safety limit.");
    entries.push({ path, method, crc, compressedSize, uncompressedSize, localOffset });
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  if (entries.length !== fileCount) fail("The ZIP file count does not match its directory.");
  const manifests = entries.filter((entry) => /(^|\/)kujo-(theme|plugin)\.json$/.test(entry.path));
  if (manifests.length !== 1) fail("The ZIP must contain exactly one kujo-theme.json or kujo-plugin.json manifest.");
  const entry = manifests[0];
  if (entry.uncompressedSize > MAX_MANIFEST) fail("The extension manifest is too large.");
  if (view.getUint32(entry.localOffset, true) !== 0x04034b50) fail("The ZIP manifest entry is malformed.");
  const localNameLength = view.getUint16(entry.localOffset + 26, true);
  const localExtraLength = view.getUint16(entry.localOffset + 28, true);
  const dataOffset = entry.localOffset + 30 + localNameLength + localExtraLength;
  if (dataOffset + entry.compressedSize > bytes.length) fail("The ZIP manifest data is truncated.");
  const compressed = bytes.subarray(dataOffset, dataOffset + entry.compressedSize);
  const manifestBytes = entry.method === 0 ? compressed : inflateRawSync(compressed, { maxOutputLength: MAX_MANIFEST + 1 });
  if (manifestBytes.length !== entry.uncompressedSize || crc32(manifestBytes) !== entry.crc) fail("The ZIP manifest failed its integrity check.");
  let manifest;
  try { manifest = JSON.parse(decoder.decode(manifestBytes)); } catch { fail("The extension manifest is not valid JSON."); }
  return { manifest, fileCount: entries.length, uncompressedBytes: expanded, manifestPath: entry.path };
}

const archivePath = process.argv[2];
if (!archivePath) fail("Usage: node scripts/read-extension-package.mjs <package.zip>");
const bytes = await readFile(archivePath);
if (!bytes.length || bytes.length > MAX_ARCHIVE) fail("The ZIP must be 16 MB or smaller.");
const inspected = inspectZip(bytes);
process.stdout.write(JSON.stringify({
  manifest: inspected.manifest,
  package: {
    format: "zip",
    filename: basename(archivePath),
    size_bytes: bytes.length,
    uncompressed_bytes: inspected.uncompressedBytes,
    file_count: inspected.fileCount,
    manifest_path: inspected.manifestPath,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  },
}));
