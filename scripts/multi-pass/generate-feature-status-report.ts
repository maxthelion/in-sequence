#!/usr/bin/env bun

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { relative, resolve } from "node:path";

type FeatureRow = {
  feature: string;
  intent: string;
  status: string;
  category: "active" | "complete" | "inventory" | "deferred" | "attention" | "unknown";
};

type Options = {
  project: string;
  input: string;
  outDir: string;
};

function parseArgs(argv: string[]): Options {
  let project = process.cwd();
  let input = ".meta/multipass/state/pm-loop-feature-table.md";
  let outDir = ".meta/multipass/runtime/reports";

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    if (arg === "--project" && next) {
      project = next;
      index += 1;
    } else if (arg === "--input" && next) {
      input = next;
      index += 1;
    } else if (arg === "--out-dir" && next) {
      outDir = next;
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    }
  }

  return {
    project: resolve(project),
    input,
    outDir,
  };
}

function printHelp(): void {
  console.log(`Generate the multi-pass feature status HTML report.

Usage:
  bun scripts/multi-pass/generate-feature-status-report.ts --project /path/to/project

Options:
  --project <path>   Project root. Defaults to cwd.
  --input <path>     Markdown feature table relative to project root.
  --out-dir <path>   Report output directory relative to project root.
`);
}

function splitMarkdownRow(line: string): string[] {
  const trimmed = line.trim();
  const inner = trimmed.startsWith("|") ? trimmed.slice(1) : trimmed;
  const withoutTrailing = inner.endsWith("|") ? inner.slice(0, -1) : inner;
  return withoutTrailing.split("|").map((cell) => cell.trim());
}

function classifyStatus(status: string): FeatureRow["category"] {
  const lower = status.toLowerCase();
  if (lower.includes("active build loop") || lower.includes("awaiting") || lower.includes("blocked")) {
    return "active";
  }
  if (lower.includes("complete") || lower.includes("built and merged") || lower.includes("terminal build loop")) {
    return "complete";
  }
  if (lower.includes("deferred")) {
    return "deferred";
  }
  if (lower.includes("human") || lower.includes("product-owner") || lower.includes("approval")) {
    return "attention";
  }
  if (lower.includes("inventory") || lower.includes("not ready") || lower.includes("prototype-review")) {
    return "inventory";
  }
  return "unknown";
}

function parseFeatureTable(markdown: string): FeatureRow[] {
  const rows = markdown
    .split(/\r?\n/)
    .filter((line) => line.trim().startsWith("|"))
    .map(splitMarkdownRow)
    .filter((cells) => cells.length >= 3);

  const dataRows = rows.filter((cells) => {
    const first = cells[0].toLowerCase();
    return first !== "feature" && !/^[-: ]+$/.test(cells[0]);
  });

  return dataRows.map(([feature, intent, status]) => ({
    feature,
    intent,
    status,
    category: classifyStatus(status),
  }));
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function inlineMarkdown(value: string): string {
  return escapeHtml(value).replace(/`([^`]+)`/g, "<code>$1</code>");
}

function renderHtml(args: {
  rows: FeatureRow[];
  generatedAt: string;
  inputPath: string;
  jsonName: string;
  swimlanesExists: boolean;
}): string {
  const counts = args.rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.category] = (acc[row.category] ?? 0) + 1;
    return acc;
  }, {});

  const categoryOrder: FeatureRow["category"][] = [
    "active",
    "complete",
    "inventory",
    "deferred",
    "attention",
    "unknown",
  ];

  const cards = categoryOrder
    .filter((category) => counts[category])
    .map(
      (category) => `
        <button class="metric" data-filter="${category}">
          <span>${escapeHtml(labelFor(category))}</span>
          <strong>${counts[category]}</strong>
        </button>`,
    )
    .join("");

  const rows = args.rows
    .map(
      (row) => `
        <tr data-category="${row.category}">
          <td>
            <strong>${inlineMarkdown(row.feature)}</strong>
            <span class="badge ${row.category}">${escapeHtml(labelFor(row.category))}</span>
          </td>
          <td>${inlineMarkdown(row.intent)}</td>
          <td>${inlineMarkdown(row.status)}</td>
        </tr>`,
    )
    .join("");

  const swimlanesLink = args.swimlanesExists
    ? `<a href="./loop-actor-swimlanes-last-24h.html">Swimlanes</a>`
    : `<span class="disabled">Swimlanes missing</span>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multi-pass Feature Status</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1118;
      --panel: #161b24;
      --panel-2: #1e2530;
      --line: #2c3544;
      --text: #edf2fb;
      --muted: #a8b1c2;
      --active: #36c5f0;
      --complete: #5ee28f;
      --inventory: #a99bff;
      --deferred: #f3b85b;
      --attention: #ff7285;
      --unknown: #9aa4b2;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.45 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    main {
      width: min(1440px, calc(100vw - 32px));
      margin: 24px auto 48px;
    }
    header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 18px;
    }
    h1 {
      margin: 0 0 4px;
      font-size: 24px;
      letter-spacing: 0;
    }
    .subtle { color: var(--muted); }
    nav {
      display: flex;
      gap: 12px;
      align-items: center;
      flex-wrap: wrap;
    }
    a { color: #7bdcff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .disabled { color: #687386; }
    .toolbar, .metrics {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
      margin-bottom: 14px;
    }
    .metrics {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }
    .metric {
      appearance: none;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel-2);
      color: var(--text);
      min-width: 132px;
      padding: 10px 12px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      cursor: pointer;
    }
    .metric[aria-pressed="true"] {
      outline: 2px solid var(--active);
      outline-offset: 1px;
    }
    .toolbar {
      display: grid;
      grid-template-columns: minmax(180px, 1fr) auto;
      gap: 12px;
      align-items: center;
    }
    input {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #0f141d;
      color: var(--text);
      padding: 10px 12px;
      font: inherit;
    }
    .clear {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      color: var(--text);
      padding: 10px 12px;
      font: inherit;
      cursor: pointer;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }
    th, td {
      border-bottom: 1px solid var(--line);
      padding: 12px;
      text-align: left;
      vertical-align: top;
    }
    th {
      position: sticky;
      top: 0;
      background: #111720;
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .08em;
      z-index: 1;
    }
    tr:last-child td { border-bottom: 0; }
    td:first-child { width: 22%; }
    td:nth-child(2) { width: 34%; }
    code {
      border-radius: 4px;
      background: #0c1017;
      color: #d4dced;
      padding: 1px 4px;
    }
    .badge {
      display: inline-flex;
      margin-top: 8px;
      width: max-content;
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 12px;
      font-weight: 700;
      color: #081019;
      background: var(--unknown);
    }
    .badge.active { background: var(--active); }
    .badge.complete { background: var(--complete); }
    .badge.inventory { background: var(--inventory); }
    .badge.deferred { background: var(--deferred); }
    .badge.attention { background: var(--attention); }
    .empty {
      display: none;
      border: 1px dashed var(--line);
      border-radius: 8px;
      color: var(--muted);
      padding: 24px;
      text-align: center;
      margin-top: 14px;
    }
    @media (max-width: 760px) {
      header, .toolbar { display: block; }
      nav { margin-top: 12px; }
      .clear { margin-top: 10px; width: 100%; }
      table, thead, tbody, th, td, tr { display: block; }
      thead { display: none; }
      tr { border-bottom: 1px solid var(--line); }
      td { width: 100% !important; border-bottom: 0; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Multi-pass Feature Status</h1>
        <div class="subtle">Generated ${escapeHtml(args.generatedAt)} from <code>${escapeHtml(args.inputPath)}</code></div>
      </div>
      <nav>
        ${swimlanesLink}
        <a href="./${escapeHtml(args.jsonName)}">JSON</a>
      </nav>
    </header>

    <section class="metrics" aria-label="Feature counts">
      <button class="metric" data-filter="all" aria-pressed="true">
        <span>All</span>
        <strong>${args.rows.length}</strong>
      </button>
      ${cards}
    </section>

    <section class="toolbar" aria-label="Feature filters">
      <input id="search" type="search" placeholder="Filter by feature, intent, status, branch, commit...">
      <button class="clear" id="clear">Clear</button>
    </section>

    <table>
      <thead>
        <tr>
          <th>Feature</th>
          <th>Intent</th>
          <th>Current Status</th>
        </tr>
      </thead>
      <tbody id="rows">
        ${rows}
      </tbody>
    </table>
    <div class="empty" id="empty">No features match this filter.</div>
  </main>

  <script>
    const search = document.querySelector("#search");
    const rows = Array.from(document.querySelectorAll("tbody tr"));
    const empty = document.querySelector("#empty");
    const buttons = Array.from(document.querySelectorAll("[data-filter]"));
    let category = "all";

    function applyFilters() {
      const text = search.value.trim().toLowerCase();
      let shown = 0;
      for (const row of rows) {
        const categoryMatch = category === "all" || row.dataset.category === category;
        const textMatch = !text || row.textContent.toLowerCase().includes(text);
        const visible = categoryMatch && textMatch;
        row.style.display = visible ? "" : "none";
        if (visible) shown += 1;
      }
      empty.style.display = shown === 0 ? "block" : "none";
    }

    for (const button of buttons) {
      button.addEventListener("click", () => {
        category = button.dataset.filter;
        for (const candidate of buttons) {
          candidate.setAttribute("aria-pressed", String(candidate === button));
        }
        applyFilters();
      });
    }

    document.querySelector("#clear").addEventListener("click", () => {
      category = "all";
      search.value = "";
      for (const button of buttons) {
        button.setAttribute("aria-pressed", String(button.dataset.filter === "all"));
      }
      applyFilters();
    });

    search.addEventListener("input", applyFilters);
  </script>
</body>
</html>
`;
}

function renderIndex(args: {
  generatedAt: string;
  featureCount: number;
  featureHtmlName: string;
  featureJsonName: string;
  swimlanesExists: boolean;
  actorTimelineExists: boolean;
}): string {
  const swimlaneCard = args.swimlanesExists
    ? `<a class="card" href="./loop-actor-swimlanes-last-24h.html"><span>Swimlanes</span><strong>Actor runtime over last 24h</strong></a>`
    : `<div class="card disabled"><span>Swimlanes</span><strong>Not generated yet</strong></div>`;
  const actorTimelineCard = args.actorTimelineExists
    ? `<a class="card" href="./actor-timeline-last-24h.html"><span>Actor Timeline</span><strong>Legacy actor activity view</strong></a>`
    : `<div class="card disabled"><span>Actor Timeline</span><strong>Not generated yet</strong></div>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multi-pass Reports</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1118;
      --panel: #161b24;
      --line: #2c3544;
      --text: #edf2fb;
      --muted: #a8b1c2;
      --accent: #36c5f0;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.45 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    main {
      width: min(980px, calc(100vw - 32px));
      margin: 32px auto;
    }
    h1 { margin: 0 0 4px; font-size: 24px; letter-spacing: 0; }
    .subtle { color: var(--muted); margin-bottom: 18px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 12px;
    }
    .card {
      display: block;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 16px;
      color: var(--text);
      text-decoration: none;
    }
    .card:hover {
      border-color: var(--accent);
    }
    .card span {
      display: block;
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .08em;
      margin-bottom: 8px;
    }
    .card strong {
      display: block;
      font-size: 16px;
    }
    .disabled {
      opacity: .55;
      pointer-events: none;
    }
    .note {
      border: 1px dashed var(--line);
      border-radius: 8px;
      color: var(--muted);
      margin-top: 16px;
      padding: 14px;
    }
    code {
      border-radius: 4px;
      background: #0c1017;
      color: #d4dced;
      padding: 1px 4px;
    }
    a.inline { color: #7bdcff; }
  </style>
</head>
<body>
  <main>
    <h1>Multi-pass Reports</h1>
    <div class="subtle">Generated ${escapeHtml(args.generatedAt)}</div>
    <section class="grid">
      <a class="card" href="./${escapeHtml(args.featureHtmlName)}">
        <span>Features</span>
        <strong>${args.featureCount} roadmap features</strong>
      </a>
      ${swimlaneCard}
      ${actorTimelineCard}
      <a class="card" href="./${escapeHtml(args.featureJsonName)}">
        <span>Feature Data</span>
        <strong>Machine-readable JSON</strong>
      </a>
    </section>
    <div class="note">
      KPI health is still produced elsewhere in the loop. This index is the stable report landing page; add KPI HTML here when that report has a compact generated artifact.
    </div>
  </main>
</body>
</html>
`;
}

function labelFor(category: FeatureRow["category"] | "all"): string {
  switch (category) {
    case "active":
      return "Active";
    case "complete":
      return "Complete";
    case "inventory":
      return "Inventory";
    case "deferred":
      return "Deferred";
    case "attention":
      return "Attention";
    case "unknown":
      return "Unknown";
    case "all":
      return "All";
  }
}

function main(): void {
  const options = parseArgs(process.argv.slice(2));
  const inputPath = resolve(options.project, options.input);
  const outDir = resolve(options.project, options.outDir);

  if (!existsSync(inputPath)) {
    throw new Error(`Feature table not found: ${inputPath}`);
  }

  const markdown = readFileSync(inputPath, "utf8");
  const rows = parseFeatureTable(markdown);
  const generatedAt = new Date().toISOString();

  mkdirSync(outDir, { recursive: true });

  const source = relative(options.project, inputPath);
  const jsonName = "feature-status.json";
  const htmlName = "feature-status.html";
  const indexName = "index.html";
  const jsonPath = resolve(outDir, jsonName);
  const htmlPath = resolve(outDir, htmlName);
  const indexPath = resolve(outDir, indexName);
  const swimlanesExists = existsSync(resolve(outDir, "loop-actor-swimlanes-last-24h.html"));
  const actorTimelineExists = existsSync(resolve(outDir, "actor-timeline-last-24h.html"));

  writeFileSync(
    jsonPath,
    `${JSON.stringify({ generatedAt, source, rows }, null, 2)}\n`,
    "utf8",
  );
  writeFileSync(
    htmlPath,
    renderHtml({
      rows,
      generatedAt,
      inputPath: source,
      jsonName,
      swimlanesExists,
    }),
    "utf8",
  );
  writeFileSync(
    indexPath,
    renderIndex({
      generatedAt,
      featureCount: rows.length,
      featureHtmlName: htmlName,
      featureJsonName: jsonName,
      swimlanesExists,
      actorTimelineExists,
    }),
    "utf8",
  );

  console.log(`Wrote ${htmlPath}`);
  console.log(`Wrote ${jsonPath}`);
  console.log(`Wrote ${indexPath}`);
}

main();
