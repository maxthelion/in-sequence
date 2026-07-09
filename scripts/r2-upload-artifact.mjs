#!/usr/bin/env node
import { createHash, createHmac } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const textEncoder = new TextEncoder();

function usage() {
  console.log(`Usage:
  scripts/r2-upload-artifact.mjs FILE [options]

Options:
  --bucket BUCKET             R2 bucket. Env: R2_DISTRIBUTION_BUCKET, R2_BUCKET
  --endpoint URL              R2 S3 endpoint. Env: R2_DISTRIBUTION_ENDPOINT, R2_ENDPOINT
  --access-key-id KEY         Env: R2_DISTRIBUTION_ACCESS_KEY_ID, R2_ACCESS_KEY_ID
  --secret-access-key SECRET  Env: R2_DISTRIBUTION_SECRET_ACCESS_KEY, R2_SECRET_ACCESS_KEY
  --region REGION             Defaults to env R2_REGION, then auto
  --prefix PREFIX             Defaults to env R2_DISTRIBUTION_PREFIX, then releases/developer-id
  --key KEY                   Full object key. Defaults to PREFIX/basename(FILE)
  --latest-key KEY            Also write latest release JSON to this key.
                              Env: R2_DISTRIBUTION_LATEST_KEY
  --content-type TYPE         Defaults from extension
  --dry-run                   Print planned upload without writing to R2

Env files are loaded, when present, from:
  $R2_ENV_FILE
  scripts/distribution.r2.env
  scripts/visual-scenarios/.env
  .env
  ../bug-reporter/.env
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
    path.join(root, "scripts/distribution.r2.env"),
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

function contentTypeFor(file) {
  const extension = path.extname(file).toLowerCase();
  if (extension === ".dmg") return "application/x-apple-diskimage";
  if (extension === ".zip") return "application/zip";
  if (extension === ".json") return "application/json";
  return "application/octet-stream";
}

function signedPut({ cfg, key, body, contentType }) {
  const url = new URL(`${cfg.endpoint}/${cfg.bucket}/${encodeKey(key)}`);
  const now = new Date();
  const xAmzDate = amzDate(now);
  const dateStamp = xAmzDate.slice(0, 8);
  const payloadHash = sha256Hex(body);
  const canonicalHeaders = [
    `content-type:${contentType}`,
    `host:${url.host}`,
    `x-amz-content-sha256:${payloadHash}`,
    `x-amz-date:${xAmzDate}`,
  ].join("\n") + "\n";
  const signedHeaderNames = "content-type;host;x-amz-content-sha256;x-amz-date";
  const canonicalRequest = [
    "PUT",
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
      "Content-Type": contentType,
      "x-amz-content-sha256": payloadHash,
      "x-amz-date": xAmzDate,
    },
  };
}

async function putObject(cfg, key, body, contentType) {
  const signed = signedPut({ cfg, key, body, contentType });
  const res = await fetch(signed.url, {
    method: "PUT",
    headers: signed.headers,
    body,
  });
  if (!res.ok) throw new Error(`PUT ${key} failed: HTTP ${res.status} ${await res.text()}`);
}

function parseArgs(argv) {
  const options = {
    file: "",
    bucket: "",
    endpoint: "",
    accessKeyId: "",
    secretAccessKey: "",
    region: "",
    prefix: "",
    key: "",
    latestKey: "",
    contentType: "",
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else if (arg === "--bucket") {
      options.bucket = argv[++i] || "";
    } else if (arg === "--endpoint") {
      options.endpoint = argv[++i] || "";
    } else if (arg === "--access-key-id") {
      options.accessKeyId = argv[++i] || "";
    } else if (arg === "--secret-access-key") {
      options.secretAccessKey = argv[++i] || "";
    } else if (arg === "--region") {
      options.region = argv[++i] || "";
    } else if (arg === "--prefix") {
      options.prefix = argv[++i] || "";
    } else if (arg === "--key") {
      options.key = argv[++i] || "";
    } else if (arg === "--latest-key") {
      options.latestKey = argv[++i] || "";
    } else if (arg === "--content-type") {
      options.contentType = argv[++i] || "";
    } else if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (!options.file) {
      options.file = arg;
    } else {
      throw new Error(`Unexpected argument: ${arg}`);
    }
  }

  return options;
}

async function main() {
  const root = repoRoot();
  await loadR2Environment(root);
  const options = parseArgs(process.argv.slice(2));
  if (!options.file) {
    usage();
    process.exitCode = 64;
    return;
  }

  const file = path.resolve(options.file);
  const body = await fs.readFile(file);
  const cfg = {
    bucket: options.bucket || process.env.R2_DISTRIBUTION_BUCKET || process.env.R2_BUCKET || "",
    endpoint: (options.endpoint || process.env.R2_DISTRIBUTION_ENDPOINT || process.env.R2_ENDPOINT || "").replace(/\/+$/, ""),
    accessKeyId: options.accessKeyId || process.env.R2_DISTRIBUTION_ACCESS_KEY_ID || process.env.R2_ACCESS_KEY_ID || "",
    secretAccessKey: options.secretAccessKey || process.env.R2_DISTRIBUTION_SECRET_ACCESS_KEY || process.env.R2_SECRET_ACCESS_KEY || "",
    region: options.region || process.env.R2_REGION || "auto",
  };
  const missing = [];
  if (!cfg.bucket) missing.push("R2_DISTRIBUTION_BUCKET or R2_BUCKET");
  if (!cfg.endpoint) missing.push("R2_DISTRIBUTION_ENDPOINT or R2_ENDPOINT");
  if (!cfg.accessKeyId) missing.push("R2_DISTRIBUTION_ACCESS_KEY_ID or R2_ACCESS_KEY_ID");
  if (!cfg.secretAccessKey) missing.push("R2_DISTRIBUTION_SECRET_ACCESS_KEY or R2_SECRET_ACCESS_KEY");
  if (missing.length) throw new Error(`R2 upload missing ${missing.join(", ")}`);

  const prefix = trimSlashes(options.prefix || process.env.R2_DISTRIBUTION_PREFIX || "releases/developer-id");
  const key = trimSlashes(options.key || `${prefix}/${path.basename(file)}`);
  const latestKey = trimSlashes(options.latestKey || process.env.R2_DISTRIBUTION_LATEST_KEY || "");
  const contentType = options.contentType || contentTypeFor(file);
  const sha256 = sha256Hex(body);

  if (!options.dryRun) await putObject(cfg, key, body, contentType);

  const publicBase = (process.env.R2_DISTRIBUTION_PUBLIC_BASE_URL || process.env.R2_PUBLIC_BASE_URL || "").replace(/\/+$/, "");
  const commit = git(["rev-parse", "--short=12", "HEAD"], "");
  const branch = git(["rev-parse", "--abbrev-ref", "HEAD"], "");
  const result = {
    file,
    name: "In Sequence",
    fileName: path.basename(file),
    bucket: cfg.bucket,
    key,
    bytes: body.length,
    sha256,
    contentType,
    commit,
    branch,
    createdAt: new Date().toISOString(),
    uploaded: !options.dryRun,
  };
  if (publicBase) result.publicUrl = `${publicBase}/${encodeKey(key)}`;
  if (latestKey) {
    const latest = {
      name: result.name,
      fileName: result.fileName,
      key: result.key,
      publicUrl: result.publicUrl,
      bytes: result.bytes,
      sha256: result.sha256,
      contentType: result.contentType,
      commit: result.commit,
      branch: result.branch,
      createdAt: result.createdAt,
    };
    if (!options.dryRun) {
      await putObject(
        cfg,
        latestKey,
        Buffer.from(`${JSON.stringify(latest, null, 2)}\n`),
        "application/json"
      );
    }
    result.latestKey = latestKey;
  }
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
