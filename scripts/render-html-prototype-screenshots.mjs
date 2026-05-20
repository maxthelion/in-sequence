#!/usr/bin/env node

import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn } from "node:child_process";

const chromePath =
  process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function usage() {
  console.error(
    [
      "Usage:",
      "  node scripts/render-html-prototype-screenshots.mjs <html-file-or-url> <out-dir> <name=js>...",
      "",
      "Example:",
      "  node scripts/render-html-prototype-screenshots.mjs docs/foo.html docs/foo/rendered source=\"setState('clip')\"",
    ].join("\n"),
  );
}

const [, , input, outDirArg, ...stateArgs] = process.argv;
if (!input || !outDirArg || stateArgs.length === 0) {
  usage();
  process.exit(2);
}

if (typeof WebSocket === "undefined") {
  console.error("This script needs a Node runtime with global WebSocket support.");
  process.exit(2);
}

const url = input.match(/^https?:|^file:/)
  ? input
  : pathToFileURL(resolve(input)).toString();
const outDir = resolve(outDirArg);
const states = stateArgs.map((arg) => {
  const splitAt = arg.indexOf("=");
  if (splitAt < 1) {
    console.error(`Invalid state argument: ${arg}`);
    usage();
    process.exit(2);
  }
  return {
    name: arg.slice(0, splitAt).replace(/[^a-zA-Z0-9._-]/g, "-"),
    expression: arg.slice(splitAt + 1),
  };
});

async function wait(ms) {
  return new Promise((resolveWait) => setTimeout(resolveWait, ms));
}

async function waitForExit(child, timeoutMs = 3000) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  await new Promise((resolveExit) => {
    const timeout = setTimeout(resolveExit, timeoutMs);
    child.once("exit", () => {
      clearTimeout(timeout);
      resolveExit();
    });
  });
}

async function fetchJson(urlToFetch) {
  const response = await fetch(urlToFetch);
  if (!response.ok) {
    throw new Error(`${urlToFetch} returned ${response.status}`);
  }
  return response.json();
}

async function findFreePort() {
  for (let port = 9223; port < 9323; port += 1) {
    try {
      await fetch(`http://127.0.0.1:${port}/json/version`, {
        signal: AbortSignal.timeout(100),
      });
    } catch {
      return port;
    }
  }
  throw new Error("Could not find a free Chrome remote-debugging port.");
}

async function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  const pending = new Map();
  let nextId = 1;

  await new Promise((resolveOpen, rejectOpen) => {
    ws.addEventListener("open", resolveOpen, { once: true });
    ws.addEventListener("error", rejectOpen, { once: true });
  });

  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (!message.id) return;
    const waiter = pending.get(message.id);
    if (!waiter) return;
    pending.delete(message.id);
    if (message.error) {
      waiter.reject(new Error(`${message.error.message}: ${message.error.data || ""}`));
    } else {
      waiter.resolve(message.result || {});
    }
  });

  return {
    send(method, params = {}) {
      const id = nextId++;
      ws.send(JSON.stringify({ id, method, params }));
      return new Promise((resolveSend, rejectSend) => {
        pending.set(id, { resolve: resolveSend, reject: rejectSend });
      });
    },
    close() {
      ws.close();
    },
  };
}

const userDataDir = await mkdtemp(join(tmpdir(), "prototype-render-"));
const port = await findFreePort();
await mkdir(outDir, { recursive: true });

const chrome = spawn(chromePath, [
  "--headless=new",
  "--disable-gpu",
  "--disable-background-networking",
  "--disable-sync",
  "--hide-scrollbars",
  "--metrics-recording-only",
  "--mute-audio",
  "--no-first-run",
  "--no-default-browser-check",
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${userDataDir}`,
  "--window-size=1280,900",
  "about:blank",
]);

chrome.stderr.on("data", (chunk) => {
  if (process.env.DEBUG_CHROME_RENDERER === "1") {
    process.stderr.write(chunk);
  }
});

try {
  let version;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    try {
      version = await fetchJson(`http://127.0.0.1:${port}/json/version`);
      break;
    } catch {
      await wait(100);
    }
  }
  if (!version?.webSocketDebuggerUrl) {
    throw new Error("Chrome did not expose a DevTools websocket.");
  }

  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  const pageTarget = targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
  if (!pageTarget) {
    throw new Error("Chrome did not expose a page DevTools target.");
  }

  const cdp = await connect(pageTarget.webSocketDebuggerUrl);
  await cdp.send("Page.enable");
  await cdp.send("Runtime.enable");
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 1280,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });

  for (const state of states) {
    await cdp.send("Page.navigate", { url });
    await wait(700);
    const result = await cdp.send("Runtime.evaluate", {
      expression: state.expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (result.exceptionDetails) {
      throw new Error(`State ${state.name} failed: ${result.exceptionDetails.text}`);
    }
    await wait(300);
    const screenshot = await cdp.send("Page.captureScreenshot", {
      format: "png",
      fromSurface: true,
      captureBeyondViewport: false,
    });
    const outputPath = join(outDir, `${state.name}.png`);
    await writeFile(outputPath, Buffer.from(screenshot.data, "base64"));
    console.log(outputPath);
  }

  cdp.close();
} finally {
  chrome.kill("SIGTERM");
  await waitForExit(chrome);
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      await rm(userDataDir, { recursive: true, force: true });
      break;
    } catch (error) {
      if (attempt === 4) throw error;
      await wait(250);
    }
  }
}
