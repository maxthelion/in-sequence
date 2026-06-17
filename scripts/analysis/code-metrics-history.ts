#!/usr/bin/env bun

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

type Options = {
  project: string;
  outDir: string;
  commitPerDay: "latest" | "first";
  paths: string[];
};

type CommitDay = {
  date: string;
  commit: string;
  subject: string;
};

type FileMetric = {
  path: string;
  language: string;
  totalLines: number;
  sourceLines: number;
  complexity: number;
};

type DayMetric = CommitDay & {
  totalLines: number;
  sourceLines: number;
  fileCount: number;
  complexity: number;
  maxFileComplexity: number;
  topComplexFiles: FileMetric[];
};

const sourceExtensions = new Set([
  ".swift",
  ".sh",
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".py",
  ".yml",
  ".yaml",
]);

const defaultPaths = ["Sources", "Tests", "scripts", "project", "project.yml"];

function parseArgs(argv: string[]): Options {
  let project = process.cwd();
  let outDir = ".meta/multipass/runtime/reports/code-metrics-history";
  let commitPerDay: Options["commitPerDay"] = "latest";
  let paths = defaultPaths;

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    if (arg === "--project" && next) {
      project = next;
      index += 1;
    } else if (arg === "--out-dir" && next) {
      outDir = next;
      index += 1;
    } else if (arg === "--commit-per-day" && (next === "latest" || next === "first")) {
      commitPerDay = next;
      index += 1;
    } else if (arg === "--paths" && next) {
      paths = next.split(",").map((path) => path.trim()).filter(Boolean);
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return {
    project: resolve(project),
    outDir,
    commitPerDay,
    paths,
  };
}

function printHelp(): void {
  console.log(`Measure source lines and estimated cyclomatic complexity across history.

Usage:
  bun scripts/analysis/code-metrics-history.ts --project /path/to/repo

Options:
  --project <path>             Repo root. Defaults to cwd.
  --out-dir <path>             Output directory. Defaults to .meta/multipass/runtime/reports/code-metrics-history.
  --commit-per-day latest|first Representative commit per calendar day. Defaults to latest.
  --paths <csv>                Top-level paths to include. Defaults to ${defaultPaths.join(",")}.

Outputs:
  code-metrics-history.html
  code-metrics-history.json
  code-metrics-history.csv

Notes:
  Complexity is a lightweight static estimate. It is useful for trends, not
  exact compiler-grade cyclomatic complexity.
`);
}

function runGit(project: string, args: string[], maxBuffer = 64 * 1024 * 1024): string {
  const result = spawnSync("git", ["-C", project, ...args], {
    encoding: "utf8",
    maxBuffer,
  });
  if (result.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed:\n${result.stderr}`);
  }
  return result.stdout;
}

function extensionOf(path: string): string {
  const match = path.match(/(\.[^.\/]+)$/);
  return match?.[1] ?? "";
}

function languageOf(path: string): string {
  const ext = extensionOf(path);
  if (ext === ".swift") return "Swift";
  if (ext === ".sh") return "Shell";
  if ([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"].includes(ext)) return "JavaScript/TypeScript";
  if (ext === ".py") return "Python";
  if ([".yml", ".yaml"].includes(ext)) return "YAML";
  return "Other";
}

function pathIncluded(path: string, includePaths: string[]): boolean {
  return includePaths.some((includePath) => path === includePath || path.startsWith(`${includePath}/`));
}

function isSourcePath(path: string, includePaths: string[]): boolean {
  if (!pathIncluded(path, includePaths)) return false;
  if (path.includes("/.build/") || path.includes("/node_modules/") || path.includes("/DerivedData/")) return false;
  if (path.endsWith(".pbxproj")) return false;
  return sourceExtensions.has(extensionOf(path));
}

function representativeCommitsByDay(project: string, commitPerDay: Options["commitPerDay"]): CommitDay[] {
  const log = runGit(project, ["log", "--date=short", "--format=%cs%x09%H%x09%s", "--reverse"]);
  const byDay = new Map<string, CommitDay>();
  for (const line of log.split("\n")) {
    if (!line.trim()) continue;
    const [date, commit, ...subjectParts] = line.split("\t");
    const item = { date, commit, subject: subjectParts.join("\t") };
    if (commitPerDay === "first" && byDay.has(date)) continue;
    byDay.set(date, item);
  }
  return [...byDay.values()];
}

function listSourceFiles(project: string, commit: string, includePaths: string[]): string[] {
  const files = runGit(project, ["ls-tree", "-r", "--name-only", commit], 16 * 1024 * 1024)
    .split("\n")
    .filter(Boolean);
  return files.filter((path) => isSourcePath(path, includePaths));
}

function stripCommentsAndStrings(content: string, language: string): string {
  let text = content.replace(/\r\n/g, "\n");

  if (language === "Shell" || language === "YAML") {
    return text
      .split("\n")
      .map((line) => {
        if (line.startsWith("#!")) return line;
        return line.replace(/(^|\s)#.*$/, "$1");
      })
      .join("\n");
  }

  text = text.replace(/\/\*[\s\S]*?\*\//g, "");
  text = text.replace(/(^|[^:])\/\/.*$/gm, "$1");
  text = text.replace(/"""[\s\S]*?"""/g, '""');
  text = text.replace(/`(?:\\.|[^`])*`/g, "``");
  text = text.replace(/"(?:\\.|[^"\\])*"/g, '""');
  text = text.replace(/'(?:\\.|[^'\\])*'/g, "''");
  return text;
}

function countMatches(text: string, regex: RegExp): number {
  return text.match(regex)?.length ?? 0;
}

function estimateComplexity(clean: string, language: string): number {
  if (language === "YAML") return 0;

  let complexity = 1;
  complexity += countMatches(clean, /\b(if|for|while|guard|catch|switch)\b/g);
  complexity += countMatches(clean, /\bcase\b/g);
  complexity += countMatches(clean, /&&|\|\|/g);

  if (language === "Swift") {
    complexity += countMatches(clean, /\btry\?/g);
    complexity += countMatches(clean, /\?\s*(?![.:?])/g);
  } else if (language === "Shell") {
    complexity += countMatches(clean, /\b(case|elif|until)\b/g);
  } else if (language === "JavaScript/TypeScript") {
    complexity += countMatches(clean, /\b(default|catch)\b/g);
    complexity += countMatches(clean, /\?\s*[^.?]/g);
  } else if (language === "Python") {
    complexity += countMatches(clean, /\b(except|elif|with)\b/g);
  }

  return complexity;
}

function measureFile(project: string, commit: string, path: string): FileMetric | null {
  const content = runGit(project, ["show", `${commit}:${path}`]);
  const language = languageOf(path);
  const totalLines = content.length === 0 ? 0 : content.split(/\r\n|\r|\n/).length;
  const clean = stripCommentsAndStrings(content, language);
  const sourceLines = clean.split("\n").filter((line) => line.trim().length > 0).length;
  if (totalLines === 0) return null;
  return {
    path,
    language,
    totalLines,
    sourceLines,
    complexity: estimateComplexity(clean, language),
  };
}

function measureCommit(project: string, day: CommitDay, paths: string[]): DayMetric {
  const files = listSourceFiles(project, day.commit, paths);
  const fileMetrics = files
    .map((file) => measureFile(project, day.commit, file))
    .filter((metric): metric is FileMetric => metric !== null);

  const topComplexFiles = [...fileMetrics]
    .sort((a, b) => b.complexity - a.complexity || b.sourceLines - a.sourceLines)
    .slice(0, 8);

  return {
    ...day,
    totalLines: sum(fileMetrics, "totalLines"),
    sourceLines: sum(fileMetrics, "sourceLines"),
    fileCount: fileMetrics.length,
    complexity: sum(fileMetrics, "complexity"),
    maxFileComplexity: topComplexFiles[0]?.complexity ?? 0,
    topComplexFiles,
  };
}

function sum<T extends Record<string, number>>(rows: T[], key: keyof T): number {
  return rows.reduce((total, row) => total + row[key], 0);
}

function csvEscape(value: string | number): string {
  const text = String(value);
  if (!/[",\n]/.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

function writeCsv(metrics: DayMetric[], path: string): void {
  const header = [
    "date",
    "commit",
    "subject",
    "fileCount",
    "totalLines",
    "sourceLines",
    "complexity",
    "maxFileComplexity",
    "topComplexFiles",
  ];
  const rows = metrics.map((metric) => [
    metric.date,
    metric.commit,
    metric.subject,
    metric.fileCount,
    metric.totalLines,
    metric.sourceLines,
    metric.complexity,
    metric.maxFileComplexity,
    metric.topComplexFiles.map((file) => `${file.path}:${file.complexity}`).join("; "),
  ]);
  writeFileSync(path, [header, ...rows].map((row) => row.map(csvEscape).join(",")).join("\n"));
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function writeHtml(metrics: DayMetric[], path: string, options: Options): void {
  const data = JSON.stringify(metrics);
  const latest = metrics[metrics.length - 1];
  const first = metrics[0];
  const sourceDelta = latest && first ? latest.sourceLines - first.sourceLines : 0;
  const complexityDelta = latest && first ? latest.complexity - first.complexity : 0;
  const rows = metrics
    .map((metric) => {
      const top = metric.topComplexFiles
        .slice(0, 3)
        .map((file) => `${htmlEscape(file.path)} (${file.complexity})`)
        .join("<br>");
      return `<tr>
        <td>${htmlEscape(metric.date)}</td>
        <td><code>${htmlEscape(metric.commit.slice(0, 8))}</code></td>
        <td>${metric.fileCount}</td>
        <td>${metric.sourceLines.toLocaleString()}</td>
        <td>${metric.complexity.toLocaleString()}</td>
        <td>${metric.maxFileComplexity.toLocaleString()}</td>
        <td>${top}</td>
      </tr>`;
    })
    .join("\n");

  writeFileSync(path, `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Code Metrics History</title>
  <style>
    :root { color-scheme: dark; --bg: #08111f; --panel: #111c2e; --line: #27364d; --text: #e9f0fb; --muted: #9fb0c6; --cyan: #3ddcff; --amber: #ffb74d; --green: #72e59a; }
    body { margin: 0; background: var(--bg); color: var(--text); font: 14px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    main { max-width: 1180px; margin: 0 auto; padding: 28px 18px 48px; }
    h1 { margin: 0 0 6px; font-size: 30px; }
    .muted { color: var(--muted); }
    .cards { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 18px 0; }
    .card, .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; }
    .card { padding: 14px; }
    .value { font-size: 26px; font-weight: 800; }
    .chart { padding: 16px; margin: 18px 0; }
    svg { width: 100%; height: 360px; display: block; overflow: visible; }
    .axis { stroke: var(--line); stroke-width: 1; }
    .loc { fill: none; stroke: var(--cyan); stroke-width: 2.5; }
    .complexity { fill: none; stroke: var(--amber); stroke-width: 2.5; }
    .dot-loc { fill: var(--cyan); }
    .dot-complexity { fill: var(--amber); }
    .legend { display: flex; gap: 18px; flex-wrap: wrap; color: var(--muted); margin-top: 8px; }
    .swatch { display: inline-block; width: 18px; height: 3px; vertical-align: middle; margin-right: 6px; }
    table { width: 100%; border-collapse: collapse; margin-top: 18px; }
    th, td { text-align: left; border-bottom: 1px solid var(--line); padding: 9px 10px; vertical-align: top; }
    th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    code { background: #1a2638; border-radius: 4px; padding: 1px 4px; }
    @media (max-width: 760px) {
      .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      main { padding: 18px 10px 36px; }
      table { font-size: 12px; }
      th:nth-child(7), td:nth-child(7) { display: none; }
    }
  </style>
</head>
<body>
<main>
  <h1>Code Metrics History</h1>
  <div class="muted">${htmlEscape(options.project)} · ${metrics.length} sampled days · ${htmlEscape(options.commitPerDay)} commit per day · paths: ${htmlEscape(options.paths.join(", "))}</div>
  <section class="cards">
    <div class="card"><div class="muted">Latest source LOC</div><div class="value">${latest?.sourceLines.toLocaleString() ?? "0"}</div></div>
    <div class="card"><div class="muted">Source LOC delta</div><div class="value">${sourceDelta >= 0 ? "+" : ""}${sourceDelta.toLocaleString()}</div></div>
    <div class="card"><div class="muted">Latest complexity</div><div class="value">${latest?.complexity.toLocaleString() ?? "0"}</div></div>
    <div class="card"><div class="muted">Complexity delta</div><div class="value">${complexityDelta >= 0 ? "+" : ""}${complexityDelta.toLocaleString()}</div></div>
  </section>
  <section class="panel chart">
    <svg id="chart" viewBox="0 0 1100 360" role="img" aria-label="Source lines and complexity over time"></svg>
    <div class="legend">
      <span><span class="swatch" style="background: var(--cyan)"></span>Source LOC</span>
      <span><span class="swatch" style="background: var(--amber)"></span>Estimated cyclomatic complexity</span>
    </div>
  </section>
  <section class="panel" style="padding: 0 0 8px;">
    <table>
      <thead><tr><th>Date</th><th>Commit</th><th>Files</th><th>Source LOC</th><th>Complexity</th><th>Max file</th><th>Top complex files</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </section>
</main>
<script>
const data = ${data};
const svg = document.getElementById("chart");
const width = 1100;
const height = 360;
const margin = { top: 20, right: 70, bottom: 52, left: 70 };
const innerW = width - margin.left - margin.right;
const innerH = height - margin.top - margin.bottom;
const maxLoc = Math.max(...data.map(d => d.sourceLines), 1);
const maxCx = Math.max(...data.map(d => d.complexity), 1);
const x = i => margin.left + (data.length <= 1 ? innerW / 2 : (i / (data.length - 1)) * innerW);
const yLoc = v => margin.top + innerH - (v / maxLoc) * innerH;
const yCx = v => margin.top + innerH - (v / maxCx) * innerH;
function pathFor(key, scale) {
  return data.map((d, i) => \`\${i === 0 ? "M" : "L"}\${x(i).toFixed(1)},\${scale(d[key]).toFixed(1)}\`).join(" ");
}
function el(name, attrs = {}, text = "") {
  const node = document.createElementNS("http://www.w3.org/2000/svg", name);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value));
  if (text) node.textContent = text;
  svg.appendChild(node);
  return node;
}
for (let tick = 0; tick <= 4; tick++) {
  const y = margin.top + (tick / 4) * innerH;
  el("line", { x1: margin.left, y1: y, x2: width - margin.right, y2: y, class: "axis", opacity: tick === 4 ? 1 : 0.55 });
  el("text", { x: margin.left - 10, y: y + 4, "text-anchor": "end", fill: "#9fb0c6", "font-size": 11 }, Math.round(maxLoc * (1 - tick / 4)).toLocaleString());
  el("text", { x: width - margin.right + 10, y: y + 4, fill: "#9fb0c6", "font-size": 11 }, Math.round(maxCx * (1 - tick / 4)).toLocaleString());
}
el("path", { d: pathFor("sourceLines", yLoc), class: "loc" });
el("path", { d: pathFor("complexity", yCx), class: "complexity" });
data.forEach((d, i) => {
  const title = \`\${d.date}\\nLOC: \${d.sourceLines}\\nComplexity: \${d.complexity}\\n\${d.subject}\`;
  const locDot = el("circle", { cx: x(i), cy: yLoc(d.sourceLines), r: 3.2, class: "dot-loc" });
  locDot.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "title")).textContent = title;
  const cxDot = el("circle", { cx: x(i), cy: yCx(d.complexity), r: 3.2, class: "dot-complexity" });
  cxDot.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "title")).textContent = title;
});
const labelEvery = Math.max(1, Math.ceil(data.length / 10));
data.forEach((d, i) => {
  if (i % labelEvery !== 0 && i !== data.length - 1) return;
  el("text", { x: x(i), y: height - 20, "text-anchor": "middle", fill: "#9fb0c6", "font-size": 11 }, d.date.slice(5));
});
el("text", { x: margin.left, y: 14, fill: "#3ddcff", "font-size": 12 }, "Source LOC");
el("text", { x: width - margin.right, y: 14, "text-anchor": "end", fill: "#ffb74d", "font-size": 12 }, "Complexity");
</script>
</body>
</html>
`);
}

function ensureDir(path: string): void {
  const dir = path.endsWith("/") ? path : dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function main(): void {
  const options = parseArgs(process.argv.slice(2));
  const outDir = resolve(options.project, options.outDir);
  mkdirSync(outDir, { recursive: true });

  const days = representativeCommitsByDay(options.project, options.commitPerDay);
  const metrics = days.map((day, index) => {
    process.stderr.write(`Measuring ${day.date} ${day.commit.slice(0, 8)} (${index + 1}/${days.length})\n`);
    return measureCommit(options.project, day, options.paths);
  });

  const jsonPath = resolve(outDir, "code-metrics-history.json");
  const csvPath = resolve(outDir, "code-metrics-history.csv");
  const htmlPath = resolve(outDir, "code-metrics-history.html");
  ensureDir(jsonPath);
  writeFileSync(jsonPath, `${JSON.stringify({ generatedAt: new Date().toISOString(), options, metrics }, null, 2)}\n`);
  writeCsv(metrics, csvPath);
  writeHtml(metrics, htmlPath, options);

  console.log(htmlPath);
  console.log(csvPath);
  console.log(jsonPath);
}

main();
