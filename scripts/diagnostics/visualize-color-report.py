#!/usr/bin/env python3
"""Build a static HTML dashboard for capture color-report JSON."""

from __future__ import annotations

import argparse
import html
import json
import statistics
from pathlib import Path
from urllib.parse import quote


SEGMENTS = [
    ("mid-grey", "Mid grey", "#54545c"),
    ("light-grey", "Light grey", "#c8c8c0"),
    ("chroma", "Chroma", "#00ccff"),
    ("other", "Other", "#2c2c32"),
]


def percent(row: dict, key: str) -> float:
    if key == "chroma":
        return float(row["chroma"]["percent"])
    if key == "other":
        used = (
            row["neutral"]["dark-grey"]["percent"]
            + row["neutral"]["mid-grey"]["percent"]
            + row["neutral"]["light-grey"]["percent"]
            + row["chroma"]["percent"]
        )
        return max(0.0, 100.0 - float(used))
    return float(row["neutral"][key]["percent"])


def image_href(path: Path, output_dir: Path) -> str:
    try:
        return quote(str(path.resolve().relative_to(output_dir.resolve())))
    except ValueError:
        return path.resolve().as_uri()


def capture_name(row: dict) -> str:
    return Path(row["file"]).name


def fmt(value: float, digits: int = 2) -> str:
    return f"{value:.{digits}f}%"


def crop_label(row: dict) -> str:
    crop = row.get("crop") or {}
    if crop.get("mode") == "modal-auto":
        bbox = crop.get("bbox") or []
        bbox_text = ",".join(str(value) for value in bbox) if bbox else "unknown"
        source = crop.get("source") or "modal signal"
        coverage = float(crop.get("coverage_percent", 0))
        return (
            f'<span class="crop-badge crop-modal" title="{html.escape(source)} bbox {html.escape(bbox_text)}">'
            f"Modal {coverage:.1f}%"
            "</span>"
        )
    return '<span class="crop-badge">Full</span>'


def metric_card(label: str, value: str, detail: str) -> str:
    return f"""
    <section class="metric">
      <div class="metric-label">{html.escape(label)}</div>
      <div class="metric-value">{html.escape(value)}</div>
      <div class="metric-detail">{html.escape(detail)}</div>
    </section>
    """


def swatches(entries: list[dict], limit: int = 6) -> str:
    chips = []
    for entry in entries[:limit]:
        color = html.escape(entry["hex"])
        chips.append(
            f"""
            <span class="swatch-chip" title="{color} {entry['percent']:.3f}%">
              <span class="swatch" style="background:{color}"></span>
              <span>{color}</span>
              <b>{entry['percent']:.2f}%</b>
            </span>
            """
        )
    return "\n".join(chips) or '<span class="empty">No chroma</span>'


def distribution_bar(row: dict) -> str:
    parts = []
    total = sum(percent(row, key) for key, _, _ in SEGMENTS)
    for key, label, color in SEGMENTS:
        value = percent(row, key)
        if value <= 0:
            continue
        width = 0 if total <= 0 else value / total * 100
        parts.append(
            f'<span style="width:{width:.4f}%;background:{color}" title="{html.escape(label)} {value:.3f}% of all pixels"></span>'
        )
    return f'<div class="stacked-bar" title="Dark grey excluded from this bar">{"".join(parts)}</div>'


def unexpected_bar(row: dict, max_unexpected: float) -> str:
    value = float(row["chroma"]["unexpected_percent"])
    width = 0 if max_unexpected <= 0 else value / max_unexpected * 100
    return (
        f'<div class="outlier-bar" title="{value:.5f}% unexpected chroma">'
        f'<span style="width:{width:.3f}%"></span>'
        f"</div>"
    )


def render_rows(rows: list[dict], output_dir: Path) -> str:
    max_unexpected = max(float(row["chroma"]["unexpected_percent"]) for row in rows) if rows else 0
    table_rows = []
    for index, row in enumerate(rows, start=1):
        image = Path(row["file"])
        image_link = image_href(image, output_dir)
        unexpected = float(row["chroma"]["unexpected_percent"])
        table_rows.append(
            f"""
            <tr>
              <td class="rank">{index}</td>
              <td class="capture">
                <a href="{image_link}">{html.escape(image.name)}</a>
                <img src="{image_link}" alt="{html.escape(image.name)}">
              </td>
              <td>{crop_label(row)}</td>
              <td>{distribution_bar(row)}</td>
              <td class="num">{percent(row, "dark-grey"):.2f}</td>
              <td class="num">{percent(row, "mid-grey"):.2f}</td>
              <td class="num">{percent(row, "light-grey"):.2f}</td>
              <td class="num">{percent(row, "chroma"):.2f}</td>
              <td class="outlier-cell">
                {unexpected_bar(row, max_unexpected)}
                <span>{unexpected:.5f}%</span>
              </td>
              <td class="num">{int(row["chroma"]["unexpected_count"])}</td>
              <td class="swatches">{swatches(row.get("top_chroma", []))}</td>
            </tr>
            """
        )
    return "\n".join(table_rows)


def render_outliers(rows: list[dict]) -> str:
    sorted_rows = sorted(rows, key=lambda row: row["chroma"]["unexpected_percent"], reverse=True)[:10]
    max_unexpected = max(float(row["chroma"]["unexpected_percent"]) for row in sorted_rows) if sorted_rows else 0
    items = []
    for row in sorted_rows:
        unexpected = float(row["chroma"]["unexpected_percent"])
        items.append(
            f"""
            <li>
              <span>{html.escape(capture_name(row))}</span>
              {unexpected_bar(row, max_unexpected)}
              <b>{unexpected:.5f}%</b>
              <em>{int(row["chroma"]["unexpected_count"])} px</em>
            </li>
            """
        )
    return "\n".join(items)


def render_palette(rows: list[dict]) -> str:
    totals: dict[str, float] = {}
    for row in rows:
        for entry in row.get("top_chroma", []):
            totals[entry["hex"]] = totals.get(entry["hex"], 0.0) + float(entry["percent"])
    chips = []
    for color, total in sorted(totals.items(), key=lambda item: item[1], reverse=True)[:28]:
        chips.append(
            f"""
            <span class="palette-chip">
              <span class="palette-swatch" style="background:{html.escape(color)}"></span>
              <span>{html.escape(color)}</span>
              <b>{total:.2f}</b>
            </span>
            """
        )
    return "\n".join(chips)


def render_html(rows: list[dict], report_path: Path, output_path: Path, title: str) -> str:
    dark_values = [percent(row, "dark-grey") for row in rows]
    chroma_values = [percent(row, "chroma") for row in rows]
    unexpected_values = [float(row["chroma"]["unexpected_percent"]) for row in rows]
    worst_unexpected = max(rows, key=lambda row: row["chroma"]["unexpected_percent"]) if rows else None
    highest_chroma = max(rows, key=lambda row: row["chroma"]["percent"]) if rows else None
    modal_crop_count = sum(1 for row in rows if (row.get("crop") or {}).get("mode") == "modal-auto")

    cards = [
        metric_card("Captures", str(len(rows)), report_path.name),
        metric_card("Modal crops", str(modal_crop_count), "Rows analyzed inside detected panel"),
        metric_card("Mean dark grey", fmt(statistics.mean(dark_values)), f"Max {fmt(max(dark_values))}" if dark_values else "-"),
        metric_card("Mean chroma", fmt(statistics.mean(chroma_values)), f"Max {fmt(max(chroma_values))}" if chroma_values else "-"),
        metric_card(
            "Worst unexpected",
            f"{max(unexpected_values):.5f}%" if unexpected_values else "0.00000%",
            capture_name(worst_unexpected) if worst_unexpected else "-",
        ),
        metric_card(
            "Highest chroma",
            fmt(float(highest_chroma["chroma"]["percent"])) if highest_chroma else "0.00%",
            capture_name(highest_chroma) if highest_chroma else "-",
        ),
    ]

    generated_from = html.escape(str(report_path))
    output_name = html.escape(output_path.name)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #0d0d10;
      --panel: #151518;
      --panel-2: #1d1d22;
      --border: #33333a;
      --text: #e8e8ec;
      --muted: #9a9aa4;
      --accent: #00ccff;
      --danger: #ff5257;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }}
    main {{
      width: min(1500px, calc(100vw - 48px));
      margin: 0 auto;
      padding: 32px 0 56px;
    }}
    header {{
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 24px;
      margin-bottom: 24px;
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 30px;
      letter-spacing: 0;
    }}
    .meta {{
      color: var(--muted);
      font-size: 13px;
      overflow-wrap: anywhere;
    }}
    .metrics {{
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 24px;
    }}
    .metric {{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 14px 16px;
    }}
    .metric-label {{
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .08em;
    }}
    .metric-value {{
      margin-top: 6px;
      font-size: 25px;
      font-weight: 760;
    }}
    .metric-detail {{
      margin-top: 3px;
      color: var(--muted);
      font-size: 12px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }}
    .section {{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      margin-top: 14px;
      overflow: hidden;
    }}
    .section h2 {{
      margin: 0;
      padding: 16px 18px 10px;
      font-size: 16px;
      letter-spacing: 0;
    }}
    .legend {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      padding: 0 18px 16px;
      color: var(--muted);
      font-size: 12px;
    }}
    .legend span {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }}
    .legend i {{
      width: 18px;
      height: 10px;
      border-radius: 2px;
      display: inline-block;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }}
    th {{
      position: sticky;
      top: 0;
      z-index: 1;
      background: #19191e;
      color: var(--muted);
      font-weight: 650;
      text-align: left;
      padding: 9px 10px;
      border-top: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
      white-space: nowrap;
    }}
    td {{
      padding: 8px 10px;
      border-bottom: 1px solid #25252b;
      vertical-align: middle;
    }}
    tr:hover td {{
      background: rgba(255, 255, 255, .025);
    }}
    a {{
      color: var(--text);
      text-decoration-color: rgba(0, 204, 255, .55);
      text-underline-offset: 3px;
    }}
    .rank {{
      width: 42px;
      color: var(--muted);
      text-align: right;
    }}
    .capture {{
      width: 230px;
      font-weight: 640;
    }}
    .capture img {{
      display: block;
      width: 168px;
      height: 96px;
      object-fit: cover;
      object-position: top left;
      border: 1px solid var(--border);
      border-radius: 6px;
      margin-top: 6px;
      background: #050506;
    }}
    .num {{
      text-align: right;
      font-variant-numeric: tabular-nums;
    }}
    .crop-badge {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 58px;
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 3px 8px;
      color: var(--muted);
      background: var(--panel-2);
      font-size: 11px;
      font-weight: 650;
      white-space: nowrap;
    }}
    .crop-modal {{
      color: var(--text);
      border-color: rgba(0, 204, 255, .58);
      background: rgba(0, 204, 255, .10);
    }}
    .stacked-bar {{
      width: 100%;
      min-width: 260px;
      height: 20px;
      display: flex;
      background: #24242a;
      border: 1px solid #2a2a30;
      border-radius: 5px;
      overflow: hidden;
    }}
    .stacked-bar span {{
      height: 100%;
      min-width: 1px;
    }}
    .outlier-cell {{
      width: 190px;
      font-variant-numeric: tabular-nums;
    }}
    .outlier-cell span:last-child {{
      display: inline-block;
      min-width: 76px;
      margin-left: 8px;
      text-align: right;
      color: var(--muted);
    }}
    .outlier-bar {{
      display: inline-block;
      width: 86px;
      height: 10px;
      border-radius: 999px;
      overflow: hidden;
      background: #2a1518;
      border: 1px solid #4a2228;
      vertical-align: middle;
    }}
    .outlier-bar span {{
      display: block;
      height: 100%;
      min-width: 2px;
      background: var(--danger);
    }}
    .swatches {{
      min-width: 310px;
    }}
    .swatch-chip, .palette-chip {{
      display: inline-flex;
      align-items: center;
      gap: 5px;
      margin: 2px 6px 2px 0;
      color: var(--muted);
      font-variant-numeric: tabular-nums;
    }}
    .swatch, .palette-swatch {{
      width: 14px;
      height: 14px;
      border-radius: 3px;
      border: 1px solid rgba(255,255,255,.28);
    }}
    .swatch-chip b, .palette-chip b {{
      color: var(--text);
      font-weight: 620;
    }}
    .outliers {{
      list-style: none;
      margin: 0;
      padding: 0 18px 18px;
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px 18px;
    }}
    .outliers li {{
      display: grid;
      grid-template-columns: minmax(0, 1fr) 120px 76px 54px;
      gap: 10px;
      align-items: center;
      color: var(--muted);
      font-size: 12px;
    }}
    .outliers li > span:first-child {{
      color: var(--text);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }}
    .outliers .outlier-bar {{
      width: 120px;
    }}
    .outliers b {{
      color: var(--text);
      font-variant-numeric: tabular-nums;
      text-align: right;
    }}
    .outliers em {{
      font-style: normal;
      font-variant-numeric: tabular-nums;
      text-align: right;
    }}
    .palette {{
      padding: 0 18px 18px;
    }}
    .palette-chip {{
      background: var(--panel-2);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 7px 9px;
      margin: 0 7px 7px 0;
    }}
    @media (max-width: 1100px) {{
      main {{ width: min(100vw - 24px, 1000px); }}
      header {{ display: block; }}
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .outliers {{ grid-template-columns: 1fr; }}
      .section {{ overflow-x: auto; }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>{html.escape(title)}</h1>
        <div class="meta">Generated from {generated_from}</div>
      </div>
      <div class="meta">{output_name}</div>
    </header>

    <div class="metrics">
      {"".join(cards)}
    </div>

    <section class="section">
      <h2>Distribution By Capture</h2>
      <div class="legend">
        {"".join(f'<span><i style="background:{color}"></i>{html.escape(label)}</span>' for _, label, color in SEGMENTS)}
        <span><i style="background:#111115"></i>Dark grey excluded from bars</span>
        <span><i style="background:var(--danger)"></i>Unexpected chroma, normalized separately</span>
      </div>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Capture</th>
            <th>Crop</th>
            <th>Non-dark distribution</th>
            <th>Dark</th>
            <th>Mid</th>
            <th>Light</th>
            <th>Chroma</th>
            <th>Unexpected</th>
            <th>px</th>
            <th>Top chroma swatches</th>
          </tr>
        </thead>
        <tbody>
          {render_rows(rows, output_path.parent)}
        </tbody>
      </table>
    </section>

    <section class="section">
      <h2>Unexpected Chroma Outliers</h2>
      <ul class="outliers">
        {render_outliers(rows)}
      </ul>
    </section>

    <section class="section">
      <h2>Aggregate Chroma Swatches</h2>
      <div class="palette">
        {render_palette(rows)}
      </div>
    </section>
  </main>
</body>
</html>
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create an HTML visualization for capture-color-report JSON.")
    parser.add_argument("report_json", type=Path, help="JSON emitted by capture-color-report.py --json")
    parser.add_argument("--output", type=Path, help="HTML output path")
    parser.add_argument("--title", default="Capture Color Report Dashboard", help="HTML document title")
    parser.add_argument("--sort", choices=("file", "unexpected", "chroma", "dark-grey"), default="file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = json.loads(args.report_json.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise SystemExit("visualize-color-report: expected a top-level JSON list")

    if args.sort == "unexpected":
        rows = sorted(rows, key=lambda row: row["chroma"]["unexpected_percent"], reverse=True)
    elif args.sort == "chroma":
        rows = sorted(rows, key=lambda row: row["chroma"]["percent"], reverse=True)
    elif args.sort == "dark-grey":
        rows = sorted(rows, key=lambda row: row["neutral"]["dark-grey"]["percent"], reverse=True)
    else:
        rows = sorted(rows, key=lambda row: capture_name(row))

    output = args.output or args.report_json.with_suffix(".html")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_html(rows, args.report_json, output, args.title), encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
