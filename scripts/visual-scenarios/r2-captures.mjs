#!/usr/bin/env node
import { createHash, createHmac } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const textEncoder = new TextEncoder();
const emptySha256 = sha256Hex(Buffer.alloc(0));

function usage() {
  console.log(`Usage:
  r2-captures.mjs sync [captures-dir] [--dry-run] [--prune-local] [--manifest-id <id>]
  r2-captures.mjs fetch <manifest-id> [row] [output-dir]

Environment:
  R2_BUCKET                 default: ux-captures
  R2_ENDPOINT               required for upload/download
  R2_ACCESS_KEY_ID          required for upload/download
  R2_SECRET_ACCESS_KEY      required for upload/download
  R2_REGION                 default: auto
  R2_SCREENSHOT_PREFIX      default: screenshots
  R2_MANIFEST_PREFIX        default: manifests
  R2_GALLERY_INDEX_KEY      default: site/gallery-index.json
`);
}

function git(args, fallback = "") {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (result.status !== 0) return fallback;
  return result.stdout.trim();
}

function repoRoot() {
  return git(["rev-parse", "--show-toplevel"], process.cwd());
}

function gitRootFor(file) {
  return git(["-C", path.dirname(file), "rev-parse", "--show-toplevel"], "");
}

function isTracked(file) {
  const root = gitRootFor(file);
  if (!root) return false;
  const relative = path.relative(root, file);
  const result = spawnSync("git", ["-C", root, "ls-files", "--error-unmatch", "--", relative], {
    encoding: "utf8",
    stdio: "ignore",
  });
  return result.status === 0;
}

function branchSlug(branch) {
  branch = branch.replace(/^codex\//, "");
  const slug = branch.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
  return slug || "detached";
}

function defaultCaptureDir(root) {
  if (process.env.PEEKABOO_OUTPUT_DIR) return path.resolve(process.env.PEEKABOO_OUTPUT_DIR);
  const branch = git(["rev-parse", "--abbrev-ref", "HEAD"], "detached");
  return path.join(root, ".meta/multipass/visual-review", branchSlug(branch));
}

function requiredConfig({ allowMissing = false } = {}) {
  const cfg = {
    bucket: process.env.R2_BUCKET || "ux-captures",
    endpoint: process.env.R2_ENDPOINT || "",
    accessKeyId: process.env.R2_ACCESS_KEY_ID || "",
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || "",
    region: process.env.R2_REGION || "auto",
    screenshotPrefix: trimSlashes(process.env.R2_SCREENSHOT_PREFIX || "screenshots"),
    manifestPrefix: trimSlashes(process.env.R2_MANIFEST_PREFIX || "manifests"),
  };
  const missing = [];
  if (!cfg.endpoint) missing.push("R2_ENDPOINT");
  if (!cfg.accessKeyId) missing.push("R2_ACCESS_KEY_ID");
  if (!cfg.secretAccessKey) missing.push("R2_SECRET_ACCESS_KEY");
  if (missing.length && allowMissing) return { cfg, missing };
  if (missing.length) throw new Error(`R2 sync skipped: missing ${missing.join(", ")}`);
  cfg.endpoint = cfg.endpoint.replace(/\/+$/, "");
  return { cfg, missing: [] };
}

function trimSlashes(value) {
  return value.replace(/^\/+|\/+$/g, "");
}

async function loadDotEnvFile(file) {
  let text = "";
  try {
    text = await fs.readFile(file, "utf8");
  } catch {
    return;
  }
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
}

async function loadR2Environment(root) {
  const candidates = [
    process.env.R2_ENV_FILE,
    path.join(root, "scripts/visual-scenarios/.env"),
    path.join(root, ".env"),
    path.resolve(root, "../bug-reporter/.env"),
  ].filter(Boolean);
  for (const file of candidates) {
    await loadDotEnvFile(file);
  }
}

function hmac(key, value) {
  return createHmac("sha256", key).update(value).digest();
}

function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}

function md5Hex(value) {
  return createHash("md5").update(value).digest("hex");
}

function amzDate(date) {
  return date.toISOString().replace(/[:-]|\.\d{3}/g, "");
}

function signingKey(secret, dateStamp, region) {
  const kDate = hmac(textEncoder.encode(`AWS4${secret}`), dateStamp);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, "s3");
  return hmac(kService, "aws4_request");
}

function encodeKey(key) {
  return key.split("/").map(encodeURIComponent).join("/");
}

function signedHeaders({ cfg, method, key, body = Buffer.alloc(0) }) {
  const url = new URL(`${cfg.endpoint}/${cfg.bucket}/${encodeKey(key)}`);
  const now = new Date();
  const xAmzDate = amzDate(now);
  const dateStamp = xAmzDate.slice(0, 8);
  const payloadHash = method === "GET" || method === "HEAD" ? emptySha256 : sha256Hex(body);
  const canonicalHeaders = [
    `host:${url.host}`,
    `x-amz-content-sha256:${payloadHash}`,
    `x-amz-date:${xAmzDate}`,
  ].join("\n") + "\n";
  const signedHeaderNames = "host;x-amz-content-sha256;x-amz-date";
  const canonicalRequest = [
    method,
    url.pathname,
    "",
    canonicalHeaders,
    signedHeaderNames,
    payloadHash,
  ].join("\n");
  const credentialScope = `${dateStamp}/${cfg.region}/s3/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    xAmzDate,
    credentialScope,
    sha256Hex(textEncoder.encode(canonicalRequest)),
  ].join("\n");
  const signature = createHmac("sha256", signingKey(cfg.secretAccessKey, dateStamp, cfg.region))
    .update(stringToSign)
    .digest("hex");
  return {
    url,
    headers: {
      Authorization: `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${credentialScope}, SignedHeaders=${signedHeaderNames}, Signature=${signature}`,
      "x-amz-content-sha256": payloadHash,
      "x-amz-date": xAmzDate,
    },
  };
}

async function request(cfg, method, key, body) {
  const signed = signedHeaders({ cfg, method, key, body });
  return fetch(signed.url, {
    method,
    headers: signed.headers,
    body: method === "PUT" ? body : undefined,
  });
}

async function objectExists(cfg, key) {
  const res = await request(cfg, "HEAD", key);
  if (res.status === 200) return true;
  if (res.status === 404) return false;
  throw new Error(`HEAD ${key} failed: HTTP ${res.status} ${await res.text()}`);
}

async function putObject(cfg, key, body) {
  const res = await request(cfg, "PUT", key, body);
  if (!res.ok) throw new Error(`PUT ${key} failed: HTTP ${res.status} ${await res.text()}`);
}

async function getObject(cfg, key) {
  const res = await request(cfg, "GET", key);
  if (!res.ok) throw new Error(`GET ${key} failed: HTTP ${res.status} ${await res.text()}`);
  return Buffer.from(await res.arrayBuffer());
}

async function getJsonObject(cfg, key) {
  try {
    return JSON.parse((await getObject(cfg, key)).toString("utf8"));
  } catch {
    return null;
  }
}

async function updateGalleryIndex(cfg, manifest) {
  const key = trimSlashes(process.env.R2_GALLERY_INDEX_KEY || "site/gallery-index.json");
  const existing = await getJsonObject(cfg, key);
  const current = Array.isArray(existing?.manifests) ? existing.manifests : [];
  const entry = {
    manifestId: manifest.manifestId,
    key: `${manifest.manifestPrefix}/${manifest.manifestId}.json`,
    branch: manifest.branch,
    commit: manifest.commit,
    capturedAt: manifest.capturedAt,
    captureDir: manifest.captureDir,
    rowCount: Object.keys(manifest.rows || {}).length,
  };
  const byId = new Map();
  for (const item of current) {
    if (item?.manifestId) byId.set(item.manifestId, item);
  }
  byId.set(entry.manifestId, entry);
  const body = Buffer.from(`${JSON.stringify({
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    manifests: [...byId.values()].sort((a, b) =>
      String(b.capturedAt || "").localeCompare(String(a.capturedAt || ""))
    ),
  }, null, 2)}\n`);
  await putObject(cfg, key, body);
  return key;
}

async function topLevelPngs(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".png"))
    .map((entry) => path.join(dir, entry.name))
    .sort();
}

async function syncCommand(argv) {
  const root = repoRoot();
  await loadR2Environment(root);
  let capturesDir = "";
  let dryRun = false;
  let pruneLocal = false;
  let manifestId = process.env.R2_MANIFEST_ID || "";
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--dry-run") dryRun = true;
    else if (arg === "--prune-local") pruneLocal = true;
    else if (arg === "--manifest-id") manifestId = argv[++i] || "";
    else if (!capturesDir) capturesDir = arg;
    else throw new Error(`Unexpected argument: ${arg}`);
  }

  capturesDir = path.resolve(capturesDir || defaultCaptureDir(root));
  const pngs = await topLevelPngs(capturesDir);
  if (pngs.length === 0) throw new Error(`No top-level PNG captures found in ${capturesDir}`);

  const { cfg, missing } = requiredConfig({ allowMissing: true });
  if (missing.length) {
    console.error(`R2 sync skipped: missing ${missing.join(", ")}`);
    return;
  }

  const commit = git(["rev-parse", "HEAD"], "unknown");
  const branch = git(["rev-parse", "--abbrev-ref", "HEAD"], "unknown");
  const dirty = git(["status", "--porcelain"], "") !== "";
  const safeManifestId = (manifestId || commit).replace(/[^A-Za-z0-9._-]/g, "-");
  const rows = {};
  let uploaded = 0;
  let skipped = 0;
  let pruned = 0;
  let skippedTrackedPngs = 0;

  for (const png of pngs) {
    const bytes = await fs.readFile(png);
    const md5 = md5Hex(bytes);
    const row = path.basename(png, ".png");
    const key = `${cfg.screenshotPrefix}/${md5}.png`;
    const exists = dryRun ? false : await objectExists(cfg, key);
    if (!exists) {
      if (!dryRun) await putObject(cfg, key, bytes);
      uploaded += 1;
    } else {
      skipped += 1;
    }
    rows[row] = {
      md5,
      key,
      bytes: bytes.length,
      status: "captured",
    };
  }

  const manifest = {
    schemaVersion: 1,
    manifestId: safeManifestId,
    commit,
    branch,
    dirtyWorkingTree: dirty,
    capturedAt: new Date().toISOString(),
    captureDir: path.relative(root, capturesDir),
    bucket: cfg.bucket,
    blobPrefix: cfg.screenshotPrefix,
    manifestPrefix: cfg.manifestPrefix,
    rows,
  };
  const manifestBody = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);
  const localManifestDir = path.join(root, ".meta/multipass/visual-review/manifests");
  const localManifest = path.join(localManifestDir, `${safeManifestId}.json`);
  await fs.mkdir(localManifestDir, { recursive: true });
  await fs.writeFile(localManifest, manifestBody);

  const manifestKey = `${cfg.manifestPrefix}/${safeManifestId}.json`;
  if (!dryRun) await putObject(cfg, manifestKey, manifestBody);
  const galleryIndexKey = dryRun ? "" : await updateGalleryIndex(cfg, manifest);

  if (pruneLocal && !dryRun) {
    for (const png of pngs) {
      if (isTracked(png)) {
        skippedTrackedPngs += 1;
        continue;
      }
      await fs.unlink(png);
      pruned += 1;
    }
  }

  console.log(JSON.stringify({
    manifest: path.relative(root, localManifest),
    manifestKey,
    galleryIndexKey,
    rows: Object.keys(rows).length,
    uploaded,
    skipped,
    dryRun,
    prunedLocalPngs: pruned,
    skippedTrackedPngs,
  }, null, 2));
}

async function loadManifest(root, cfg, manifestId) {
  const safeManifestId = manifestId.replace(/[^A-Za-z0-9._-]/g, "-");
  const local = path.join(root, ".meta/multipass/visual-review/manifests", `${safeManifestId}.json`);
  try {
    return JSON.parse(await fs.readFile(local, "utf8"));
  } catch {
    const body = await getObject(cfg, `${cfg.manifestPrefix}/${safeManifestId}.json`);
    await fs.mkdir(path.dirname(local), { recursive: true });
    await fs.writeFile(local, body);
    return JSON.parse(body.toString("utf8"));
  }
}

async function fetchCommand(argv) {
  const root = repoRoot();
  await loadR2Environment(root);
  const manifestId = argv[0];
  if (!manifestId) throw new Error("fetch requires <manifest-id>");
  const row = argv[1] || "";
  const outputDir = path.resolve(argv[2] || path.join(root, ".meta/multipass/visual-review/_cache", manifestId));
  const { cfg } = requiredConfig();
  const manifest = await loadManifest(root, cfg, manifestId);
  const rows = row ? { [row]: manifest.rows[row] } : manifest.rows;
  if (row && !rows[row]) throw new Error(`Manifest ${manifestId} has no row '${row}'`);
  await fs.mkdir(outputDir, { recursive: true });

  const written = [];
  for (const [name, info] of Object.entries(rows)) {
    const out = path.join(outputDir, `${name}.png`);
    try {
      await fs.access(out);
    } catch {
      const body = await getObject(cfg, info.key || `${manifest.blobPrefix}/${info.md5}.png`);
      await fs.writeFile(out, body);
    }
    written.push(out);
  }
  console.log(written.join("\n"));
}

async function main() {
  const [command, ...argv] = process.argv.slice(2);
  if (!command || command === "-h" || command === "--help") {
    usage();
    return;
  }
  if (command === "sync") return syncCommand(argv);
  if (command === "fetch") return fetchCommand(argv);
  throw new Error(`Unknown command: ${command}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
