#!/usr/bin/env bash
# usage-chart.sh — Generate an interactive HTML dashboard from Claude usage logs
#
# Reads ~/.local/share/claude-usage/usage.jsonl and produces a self-contained
# HTML file with three charts:
#   1. Session drain overlay (each 5h window as a line)
#   2. Timeline (absolute time: session pct + weekly pct)
#   3. Heatmap (day × hour activity matrix)
#
# Opens the result in the default browser.

set -euo pipefail

USAGE_LOG="{{home}}/.local/share/claude-usage/usage.jsonl"
OUTPUT="/tmp/claude-usage-chart.html"

if [[ ! -f "$USAGE_LOG" ]]; then
  echo "No usage log found at $USAGE_LOG"
  exit 1
fi

python3 << 'PYEOF' > "$OUTPUT"
import json, sys, os, math
from datetime import datetime, timedelta
from collections import defaultdict

LOG = os.path.expanduser(os.environ.get("USAGE_LOG", "~/.local/share/claude-usage/usage.jsonl"))

data = []
with open(LOG) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            data.append(json.loads(line))
        except json.JSONDecodeError:
            continue

if not data:
    print("<html><body><h1>No data</h1></body></html>")
    sys.exit(0)

# ── Session series (for overlay chart) ──────────────────
windows = defaultdict(list)
for d in data:
    wid = d.get("window_id", "?")
    reset_ts = d["reset_ts"]
    elapsed_h = (d["ts"] - (reset_ts - 5 * 3600)) / 3600
    windows[wid].append({"x": round(elapsed_h, 3), "y": d["pct"]})

session_series = []
for wid in sorted(windows.keys()):
    pts = windows[wid]
    max_pct = max(p["y"] for p in pts)
    session_series.append({"label": wid, "max_pct": max_pct, "points": pts})

# ── Timeline data ───────────────────────────────────────
timeline_ts = [d["ts"] * 1000 for d in data]  # JS expects ms
timeline_pct = [d["pct"] for d in data]
timeline_weekly = [d.get("weekly_pct") for d in data]
timeline_wids = [d.get("window_id", "") for d in data]

# Window boundaries for vertical lines
seen_wids = set()
window_boundaries = []
for d in data:
    wid = d.get("window_id", "")
    if wid and wid not in seen_wids:
        seen_wids.add(wid)
        window_boundaries.append(d["ts"] * 1000)

# ── Heatmap data (day × hour → avg pct) ────────────────
hour_buckets = defaultdict(list)
for d in data:
    dt = datetime.fromtimestamp(d["ts"])
    day_str = dt.strftime("%Y-%m-%d")
    hour = dt.hour
    hour_buckets[(day_str, hour)].append(d["pct"])

days_set = sorted(set(k[0] for k in hour_buckets.keys()))
heatmap_data = []
for day in days_set:
    for hour in range(24):
        vals = hour_buckets.get((day, hour), [])
        if vals:
            avg = round(sum(vals) / len(vals), 1)
            heatmap_data.append({"day": day, "hour": hour, "pct": avg})

# ── Generate HTML ───────────────────────────────────────

# Color helper for session lines
def session_color(max_pct, alpha=1.0):
    if max_pct < 50:
        return f"rgba(51, 187, 51, {alpha})"
    elif max_pct < 80:
        return f"rgba(230, 179, 16, {alpha})"
    else:
        return f"rgba(230, 70, 70, {alpha})"

# Build session datasets JSON
session_datasets = []
for s in session_series:
    color = session_color(s["max_pct"], 0.5)
    hover_color = session_color(s["max_pct"], 1.0)
    session_datasets.append({
        "label": s["label"],
        "data": s["points"],
        "borderColor": color,
        "backgroundColor": "transparent",
        "borderWidth": 1.5,
        "pointRadius": 0,
        "pointHoverRadius": 4,
        "pointHoverBackgroundColor": hover_color,
        "tension": 0.2,
        "showLine": True,
    })

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Claude Usage Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3"></script>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    background: #1a1a2e; color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif;
    padding: 24px; max-width: 1400px; margin: 0 auto;
  }}
  h1 {{ color: #f0a040; margin-bottom: 8px; font-size: 1.5rem; }}
  .subtitle {{ color: #888; margin-bottom: 24px; font-size: 0.9rem; }}
  .chart-container {{
    background: #16213e; border-radius: 12px; padding: 20px;
    margin-bottom: 24px; position: relative;
  }}
  .chart-container h2 {{
    color: #ccc; font-size: 1.1rem; margin-bottom: 12px; font-weight: 500;
  }}
  .chart-container .desc {{
    color: #777; font-size: 0.8rem; margin-bottom: 16px;
  }}
  canvas {{ max-height: 400px; }}
  .heatmap-wrapper {{ overflow-x: auto; }}
  #heatmapCanvas {{ min-width: 800px; }}
  .legend {{ display: flex; gap: 16px; margin-top: 8px; flex-wrap: wrap; }}
  .legend-item {{ display: flex; align-items: center; gap: 4px; font-size: 0.75rem; color: #888; }}
  .legend-swatch {{ width: 12px; height: 12px; border-radius: 2px; }}
  .stats {{
    display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px; margin-bottom: 24px;
  }}
  .stat-card {{
    background: #16213e; border-radius: 12px; padding: 16px;
  }}
  .stat-value {{ font-size: 1.8rem; font-weight: 700; color: #f0a040; }}
  .stat-label {{ font-size: 0.8rem; color: #888; margin-top: 4px; }}
</style>
</head>
<body>

<h1>✻ Claude Usage Dashboard</h1>
<p class="subtitle">
  {len(data):,} measurements · {len(session_series)} session windows ·
  {days_set[0]} → {days_set[-1]}
</p>

<!-- Stats -->
<div class="stats">
  <div class="stat-card">
    <div class="stat-value">{len(session_series)}</div>
    <div class="stat-label">Session windows tracked</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">{sum(1 for s in session_series if s['max_pct'] >= 80)}</div>
    <div class="stat-label">Sessions hitting 80%+</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">{round(sum(s['max_pct'] for s in session_series) / len(session_series), 1)}%</div>
    <div class="stat-label">Avg peak session usage</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">{data[-1].get('weekly_pct', 'N/A')}{'%' if 'weekly_pct' in data[-1] else ''}</div>
    <div class="stat-label">Current weekly usage</div>
  </div>
</div>

<!-- Chart 1: Session Drain Overlay -->
<div class="chart-container">
  <h2>Session Drain Overlay</h2>
  <p class="desc">Each line = one 5-hour session window. X = elapsed time, Y = % used.
    <span style="color:#33bb33">Green</span> = peak &lt;50%,
    <span style="color:#e6b310">Yellow</span> = peak &lt;80%,
    <span style="color:#e64646">Red</span> = peak ≥80%</p>
  <canvas id="sessionChart"></canvas>
</div>

<!-- Chart 2: Timeline -->
<div class="chart-container">
  <h2>Usage Timeline</h2>
  <p class="desc">Session % (orange) and weekly % (blue) over absolute time. Vertical lines = window boundaries.</p>
  <canvas id="timelineChart"></canvas>
</div>

<!-- Chart 3: Heatmap -->
<div class="chart-container">
  <h2>Activity Heatmap</h2>
  <p class="desc">Average session % by day and hour. Darker = higher usage.</p>
  <div class="heatmap-wrapper">
    <canvas id="heatmapCanvas"></canvas>
  </div>
  <div class="legend">
    <div class="legend-item"><div class="legend-swatch" style="background:#1a1a2e"></div> 0%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#2d4a22"></div> 25%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#7a8a20"></div> 50%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#c87820"></div> 75%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#e64646"></div> 100%</div>
  </div>
</div>

<script>
const chartDefaults = {{
  color: '#888',
  borderColor: '#333',
  font: {{ family: "-apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif" }}
}};
Chart.defaults.color = chartDefaults.color;
Chart.defaults.borderColor = '#2a2a4a';

// ── Chart 1: Session Drain Overlay ─────────────────────
const sessionDatasets = {json.dumps(session_datasets)};

new Chart(document.getElementById('sessionChart'), {{
  type: 'scatter',
  data: {{ datasets: sessionDatasets }},
  options: {{
    responsive: true,
    animation: false,
    plugins: {{
      legend: {{ display: false }},
      tooltip: {{
        callbacks: {{
          title: (items) => items[0]?.dataset.label || '',
          label: (item) => `${{item.parsed.x.toFixed(1)}}h → ${{item.parsed.y}}% used`
        }}
      }}
    }},
    scales: {{
      x: {{
        type: 'linear',
        title: {{ display: true, text: 'Elapsed time (hours)', color: '#888' }},
        min: 0, max: 5,
        ticks: {{ stepSize: 1, color: '#666' }},
        grid: {{ color: '#2a2a4a' }}
      }},
      y: {{
        title: {{ display: true, text: '% used', color: '#888' }},
        min: 0, max: 100,
        ticks: {{ color: '#666' }},
        grid: {{ color: '#2a2a4a' }}
      }}
    }}
  }}
}});

// ── Chart 2: Timeline ──────────────────────────────────
const timelineTs = {json.dumps(timeline_ts)};
const timelinePct = {json.dumps(timeline_pct)};
const timelineWeekly = {json.dumps(timeline_weekly)};
const windowBoundaries = {json.dumps(window_boundaries)};

const timelineSessionData = timelineTs.map((t, i) => ({{ x: t, y: timelinePct[i] }}));
const timelineWeeklyData = timelineTs.map((t, i) => timelineWeekly[i] != null ? {{ x: t, y: timelineWeekly[i] }} : null).filter(Boolean);

// Vertical line plugin for window boundaries
const windowLinePlugin = {{
  id: 'windowLines',
  beforeDraw(chart) {{
    const xScale = chart.scales.x;
    const ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = 'rgba(100, 100, 150, 0.2)';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    for (const ts of windowBoundaries) {{
      const x = xScale.getPixelForValue(ts);
      if (x >= xScale.left && x <= xScale.right) {{
        ctx.beginPath();
        ctx.moveTo(x, chart.chartArea.top);
        ctx.lineTo(x, chart.chartArea.bottom);
        ctx.stroke();
      }}
    }}
    ctx.restore();
  }}
}};

new Chart(document.getElementById('timelineChart'), {{
  type: 'scatter',
  data: {{
    datasets: [
      {{
        label: 'Session %',
        data: timelineSessionData,
        borderColor: 'rgba(240, 160, 64, 0.7)',
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        pointRadius: 0,
        pointHoverRadius: 3,
        showLine: true,
        tension: 0.1,
      }},
      {{
        label: 'Weekly %',
        data: timelineWeeklyData,
        borderColor: 'rgba(80, 140, 230, 0.7)',
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        pointRadius: 0,
        pointHoverRadius: 3,
        showLine: true,
        tension: 0.1,
      }}
    ]
  }},
  plugins: [windowLinePlugin],
  options: {{
    responsive: true,
    animation: false,
    plugins: {{
      legend: {{ display: true, labels: {{ color: '#888', usePointStyle: true, pointStyle: 'line' }} }},
      tooltip: {{
        callbacks: {{
          title: (items) => new Date(items[0]?.parsed.x).toLocaleString(),
          label: (item) => `${{item.dataset.label}}: ${{item.parsed.y}}%`
        }}
      }}
    }},
    scales: {{
      x: {{
        type: 'time',
        time: {{ unit: 'day', displayFormats: {{ day: 'MMM d', hour: 'MMM d HH:mm' }} }},
        title: {{ display: true, text: 'Date', color: '#888' }},
        ticks: {{ color: '#666', maxTicksLimit: 15 }},
        grid: {{ color: '#2a2a4a' }}
      }},
      y: {{
        title: {{ display: true, text: '% used', color: '#888' }},
        min: 0, max: 100,
        ticks: {{ color: '#666' }},
        grid: {{ color: '#2a2a4a' }}
      }}
    }}
  }}
}});

// ── Chart 3: Heatmap (canvas 2D) ──────────────────────
const heatmapData = {json.dumps(heatmap_data)};
const days = {json.dumps(days_set)};

(function() {{
  const canvas = document.getElementById('heatmapCanvas');
  const ctx = canvas.getContext('2d');
  const cellW = Math.max(32, Math.floor((canvas.parentElement.clientWidth - 80) / days.length));
  const cellH = 18;
  const marginLeft = 40;
  const marginTop = 24;
  canvas.width = marginLeft + days.length * cellW + 20;
  canvas.height = marginTop + 24 * cellH + 30;
  canvas.style.width = canvas.width + 'px';
  canvas.style.height = canvas.height + 'px';

  // Build lookup
  const lookup = {{}};
  for (const d of heatmapData) {{
    lookup[d.day + ':' + d.hour] = d.pct;
  }}

  function heatColor(pct) {{
    if (pct == null) return '#1a1a2e';
    const t = pct / 100;
    if (t < 0.5) {{
      const r = Math.round(26 + t * 2 * (200 - 26));
      const g = Math.round(26 + t * 2 * (140 - 26));
      const b = Math.round(46 + t * 2 * (30 - 46));
      return `rgb(${{r}},${{g}},${{b}})`;
    }} else {{
      const t2 = (t - 0.5) * 2;
      const r = Math.round(200 + t2 * (230 - 200));
      const g = Math.round(140 - t2 * (140 - 70));
      const b = Math.round(30 + t2 * (70 - 30));
      return `rgb(${{r}},${{g}},${{b}})`;
    }}
  }}

  // Hour labels (left)
  ctx.fillStyle = '#666';
  ctx.font = '10px system-ui';
  ctx.textAlign = 'right';
  for (let h = 0; h < 24; h++) {{
    if (h % 3 === 0) {{
      ctx.fillText(h + ':00', marginLeft - 4, marginTop + h * cellH + cellH * 0.7);
    }}
  }}

  // Day labels (top)
  ctx.textAlign = 'center';
  for (let i = 0; i < days.length; i++) {{
    if (i % Math.max(1, Math.floor(days.length / 10)) === 0) {{
      const short = days[i].slice(5); // MM-DD
      ctx.fillText(short, marginLeft + i * cellW + cellW / 2, marginTop - 6);
    }}
  }}

  // Cells
  for (let di = 0; di < days.length; di++) {{
    for (let h = 0; h < 24; h++) {{
      const pct = lookup[days[di] + ':' + h];
      ctx.fillStyle = heatColor(pct);
      ctx.fillRect(marginLeft + di * cellW, marginTop + h * cellH, cellW - 1, cellH - 1);
      // Text label for non-empty cells
      if (pct != null && cellW >= 28) {{
        ctx.fillStyle = pct > 60 ? '#fff' : '#aaa';
        ctx.font = '9px system-ui';
        ctx.textAlign = 'center';
        ctx.fillText(Math.round(pct) + '', marginLeft + di * cellW + cellW / 2, marginTop + h * cellH + cellH * 0.75);
      }}
    }}
  }}

  // Tooltip on hover
  canvas.addEventListener('mousemove', (e) => {{
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const di = Math.floor((mx - marginLeft) / cellW);
    const h = Math.floor((my - marginTop) / cellH);
    if (di >= 0 && di < days.length && h >= 0 && h < 24) {{
      const pct = lookup[days[di] + ':' + h];
      canvas.title = pct != null ? `${{days[di]}} ${{h}}:00 — ${{pct}}% avg` : `${{days[di]}} ${{h}}:00 — no data`;
    }} else {{
      canvas.title = '';
    }}
  }});
}})();
</script>

<p style="text-align:center; color:#555; margin-top:16px; font-size:0.75rem;">
  Generated {datetime.now().strftime("%Y-%m-%d %H:%M")} · claude-toolkit usage-chart
</p>
</body>
</html>"""

print(html)
PYEOF

export USAGE_LOG="$USAGE_LOG"
open "$OUTPUT"
