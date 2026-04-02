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

export USAGE_LOG
python3 << 'PYEOF' > "$OUTPUT"
import json, sys, os
from datetime import datetime
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
timeline_ts = [d["ts"] * 1000 for d in data]
timeline_pct = [d["pct"] for d in data]
timeline_weekly = [d.get("weekly_pct") for d in data]

seen_wids = set()
window_boundaries = []
for d in data:
    wid = d.get("window_id", "")
    if wid and wid not in seen_wids:
        seen_wids.add(wid)
        window_boundaries.append(d["ts"] * 1000)

# ── Heatmap data (day x hour -> avg pct) ────────────────
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

# ── Build session datasets ──────────────────────────────
def session_color(max_pct, alpha):
    if max_pct < 50:
        return "rgba(51, 187, 51, %s)" % alpha
    elif max_pct < 80:
        return "rgba(230, 179, 16, %s)" % alpha
    else:
        return "rgba(230, 70, 70, %s)" % alpha

session_datasets = []
for s in session_series:
    session_datasets.append({
        "label": s["label"],
        "data": s["points"],
        "borderColor": session_color(s["max_pct"], 0.5),
        "backgroundColor": "transparent",
        "borderWidth": 1.5,
        "pointRadius": 0,
        "pointHoverRadius": 4,
        "pointHoverBackgroundColor": session_color(s["max_pct"], 1.0),
        "tension": 0.2,
        "showLine": True,
    })

# ── Stats ───────────────────────────────────────────────
num_measurements = len(data)
num_windows = len(session_series)
date_from = days_set[0]
date_to = days_set[-1]
heavy_sessions = sum(1 for s in session_series if s["max_pct"] >= 80)
avg_peak = round(sum(s["max_pct"] for s in session_series) / len(session_series), 1)
current_weekly = data[-1].get("weekly_pct", "N/A")
if isinstance(current_weekly, (int, float)):
    current_weekly = str(current_weekly) + "%"
gen_time = datetime.now().strftime("%Y-%m-%d %H:%M")

# ── Inject data as JSON ────────────────────────────────
DATA_JSON = json.dumps({
    "sessionDatasets": session_datasets,
    "timelineTs": timeline_ts,
    "timelinePct": timeline_pct,
    "timelineWeekly": timeline_weekly,
    "windowBoundaries": window_boundaries,
    "heatmapData": heatmap_data,
    "days": days_set,
}, separators=(",", ":"))

# ── HTML template (no f-strings — avoids {{}} conflicts) ─
HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Claude Usage Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #1a1a2e; color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif;
    padding: 24px; max-width: 1400px; margin: 0 auto;
  }
  h1 { color: #f0a040; margin-bottom: 8px; font-size: 1.5rem; }
  .subtitle { color: #888; margin-bottom: 24px; font-size: 0.9rem; }
  .chart-container {
    background: #16213e; border-radius: 12px; padding: 20px;
    margin-bottom: 24px; position: relative;
  }
  .chart-container h2 {
    color: #ccc; font-size: 1.1rem; margin-bottom: 12px; font-weight: 500;
  }
  .chart-container .desc {
    color: #777; font-size: 0.8rem; margin-bottom: 16px;
  }
  canvas { max-height: 400px; }
  .heatmap-wrapper { overflow-x: auto; }
  #heatmapCanvas { min-width: 800px; }
  .legend { display: flex; gap: 16px; margin-top: 8px; flex-wrap: wrap; }
  .legend-item { display: flex; align-items: center; gap: 4px; font-size: 0.75rem; color: #888; }
  .legend-swatch { width: 12px; height: 12px; border-radius: 2px; }
  .stats {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px; margin-bottom: 24px;
  }
  .stat-card {
    background: #16213e; border-radius: 12px; padding: 16px;
  }
  .stat-value { font-size: 1.8rem; font-weight: 700; color: #f0a040; }
  .stat-label { font-size: 0.8rem; color: #888; margin-top: 4px; }
</style>
</head>
<body>

<h1>&#10043; Claude Usage Dashboard</h1>
<p class="subtitle">
  %%NUM_MEASUREMENTS%% measurements &middot; %%NUM_WINDOWS%% session windows &middot;
  %%DATE_FROM%% &rarr; %%DATE_TO%%
</p>

<div class="stats">
  <div class="stat-card">
    <div class="stat-value">%%NUM_WINDOWS%%</div>
    <div class="stat-label">Session windows tracked</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">%%HEAVY_SESSIONS%%</div>
    <div class="stat-label">Sessions hitting 80%+</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">%%AVG_PEAK%%%</div>
    <div class="stat-label">Avg peak session usage</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">%%CURRENT_WEEKLY%%</div>
    <div class="stat-label">Current weekly usage</div>
  </div>
</div>

<div class="chart-container">
  <h2>Session Drain Overlay</h2>
  <p class="desc">Each line = one 5-hour session window. X = elapsed time, Y = % used.
    <span style="color:#33bb33">Green</span> = peak &lt;50%,
    <span style="color:#e6b310">Yellow</span> = peak &lt;80%,
    <span style="color:#e64646">Red</span> = peak &ge;80%</p>
  <canvas id="sessionChart"></canvas>
</div>

<div class="chart-container">
  <h2>Usage Timeline</h2>
  <p class="desc">Session % (orange) and weekly % (blue) over absolute time. Vertical lines = window boundaries.</p>
  <canvas id="timelineChart"></canvas>
</div>

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
const _D = %%DATA_JSON%%;
Chart.defaults.color = '#888';
Chart.defaults.borderColor = '#2a2a4a';

// ── Chart 1: Session Drain Overlay ─────────────────────
new Chart(document.getElementById('sessionChart'), {
  type: 'scatter',
  data: { datasets: _D.sessionDatasets },
  options: {
    responsive: true,
    animation: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        callbacks: {
          title: (items) => items[0]?.dataset.label || '',
          label: (item) => item.parsed.x.toFixed(1) + 'h \u2192 ' + item.parsed.y + '% used'
        }
      }
    },
    scales: {
      x: {
        type: 'linear',
        title: { display: true, text: 'Elapsed time (hours)', color: '#888' },
        min: 0, max: 5,
        ticks: { stepSize: 1, color: '#666' },
        grid: { color: '#2a2a4a' }
      },
      y: {
        title: { display: true, text: '% used', color: '#888' },
        min: 0, max: 100,
        ticks: { color: '#666' },
        grid: { color: '#2a2a4a' }
      }
    }
  }
});

// ── Chart 2: Timeline ──────────────────────────────────
const tlSession = _D.timelineTs.map((t, i) => ({ x: t, y: _D.timelinePct[i] }));
const tlWeekly = _D.timelineTs.map((t, i) => _D.timelineWeekly[i] != null ? { x: t, y: _D.timelineWeekly[i] } : null).filter(Boolean);

const windowLinePlugin = {
  id: 'windowLines',
  beforeDraw(chart) {
    const xScale = chart.scales.x;
    const ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = 'rgba(100, 100, 150, 0.2)';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    for (const ts of _D.windowBoundaries) {
      const x = xScale.getPixelForValue(ts);
      if (x >= xScale.left && x <= xScale.right) {
        ctx.beginPath();
        ctx.moveTo(x, chart.chartArea.top);
        ctx.lineTo(x, chart.chartArea.bottom);
        ctx.stroke();
      }
    }
    ctx.restore();
  }
};

new Chart(document.getElementById('timelineChart'), {
  type: 'scatter',
  data: {
    datasets: [
      {
        label: 'Session %',
        data: tlSession,
        borderColor: 'rgba(240, 160, 64, 0.7)',
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        pointRadius: 0,
        pointHoverRadius: 3,
        showLine: true,
        tension: 0.1,
      },
      {
        label: 'Weekly %',
        data: tlWeekly,
        borderColor: 'rgba(80, 140, 230, 0.7)',
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        pointRadius: 0,
        pointHoverRadius: 3,
        showLine: true,
        tension: 0.1,
      }
    ]
  },
  plugins: [windowLinePlugin],
  options: {
    responsive: true,
    animation: false,
    plugins: {
      legend: { display: true, labels: { color: '#888', usePointStyle: true, pointStyle: 'line' } },
      tooltip: {
        callbacks: {
          title: (items) => new Date(items[0]?.parsed.x).toLocaleString(),
          label: (item) => item.dataset.label + ': ' + item.parsed.y + '%'
        }
      }
    },
    scales: {
      x: {
        type: 'time',
        time: { unit: 'day', displayFormats: { day: 'MMM d', hour: 'MMM d HH:mm' } },
        title: { display: true, text: 'Date', color: '#888' },
        ticks: { color: '#666', maxTicksLimit: 15 },
        grid: { color: '#2a2a4a' }
      },
      y: {
        title: { display: true, text: '% used', color: '#888' },
        min: 0, max: 100,
        ticks: { color: '#666' },
        grid: { color: '#2a2a4a' }
      }
    }
  }
});

// ── Chart 3: Heatmap (canvas 2D) ──────────────────────
(function() {
  var canvas = document.getElementById('heatmapCanvas');
  var ctx = canvas.getContext('2d');
  var days = _D.days;
  var cellW = Math.max(32, Math.floor((canvas.parentElement.clientWidth - 80) / days.length));
  var cellH = 18;
  var marginLeft = 40;
  var marginTop = 24;
  canvas.width = marginLeft + days.length * cellW + 20;
  canvas.height = marginTop + 24 * cellH + 30;
  canvas.style.width = canvas.width + 'px';
  canvas.style.height = canvas.height + 'px';

  var lookup = {};
  for (var k = 0; k < _D.heatmapData.length; k++) {
    var d = _D.heatmapData[k];
    lookup[d.day + ':' + d.hour] = d.pct;
  }

  function heatColor(pct) {
    if (pct == null) return '#1a1a2e';
    var t = pct / 100;
    var r, g, b;
    if (t < 0.5) {
      r = Math.round(26 + t * 2 * (200 - 26));
      g = Math.round(26 + t * 2 * (140 - 26));
      b = Math.round(46 + t * 2 * (30 - 46));
    } else {
      var t2 = (t - 0.5) * 2;
      r = Math.round(200 + t2 * (230 - 200));
      g = Math.round(140 - t2 * (140 - 70));
      b = Math.round(30 + t2 * (70 - 30));
    }
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  ctx.fillStyle = '#666';
  ctx.font = '10px system-ui';
  ctx.textAlign = 'right';
  for (var h = 0; h < 24; h++) {
    if (h % 3 === 0) {
      ctx.fillText(h + ':00', marginLeft - 4, marginTop + h * cellH + cellH * 0.7);
    }
  }

  ctx.textAlign = 'center';
  var step = Math.max(1, Math.floor(days.length / 10));
  for (var i = 0; i < days.length; i++) {
    if (i % step === 0) {
      ctx.fillText(days[i].slice(5), marginLeft + i * cellW + cellW / 2, marginTop - 6);
    }
  }

  for (var di = 0; di < days.length; di++) {
    for (var h2 = 0; h2 < 24; h2++) {
      var pct = lookup[days[di] + ':' + h2];
      ctx.fillStyle = heatColor(pct);
      ctx.fillRect(marginLeft + di * cellW, marginTop + h2 * cellH, cellW - 1, cellH - 1);
      if (pct != null && cellW >= 28) {
        ctx.fillStyle = pct > 60 ? '#fff' : '#aaa';
        ctx.font = '9px system-ui';
        ctx.textAlign = 'center';
        ctx.fillText(Math.round(pct) + '', marginLeft + di * cellW + cellW / 2, marginTop + h2 * cellH + cellH * 0.75);
      }
    }
  }

  canvas.addEventListener('mousemove', function(e) {
    var rect = canvas.getBoundingClientRect();
    var mx = e.clientX - rect.left;
    var my = e.clientY - rect.top;
    var di = Math.floor((mx - marginLeft) / cellW);
    var h = Math.floor((my - marginTop) / cellH);
    if (di >= 0 && di < days.length && h >= 0 && h < 24) {
      var pct = lookup[days[di] + ':' + h];
      canvas.title = pct != null ? days[di] + ' ' + h + ':00 — ' + pct + '% avg' : days[di] + ' ' + h + ':00 — no data';
    } else {
      canvas.title = '';
    }
  });
})();
</script>

<p style="text-align:center; color:#555; margin-top:16px; font-size:0.75rem;">
  Generated %%GEN_TIME%% &middot; claude-toolkit usage-chart
</p>
</body>
</html>"""

# Replace placeholders
for key, val in [
    ("%%DATA_JSON%%", DATA_JSON),
    ("%%NUM_MEASUREMENTS%%", "{:,}".format(num_measurements)),
    ("%%NUM_WINDOWS%%", str(num_windows)),
    ("%%DATE_FROM%%", date_from),
    ("%%DATE_TO%%", date_to),
    ("%%HEAVY_SESSIONS%%", str(heavy_sessions)),
    ("%%AVG_PEAK%%", str(avg_peak)),
    ("%%CURRENT_WEEKLY%%", str(current_weekly)),
    ("%%GEN_TIME%%", gen_time),
]:
    HTML = HTML.replace(key, val)

print(HTML)
PYEOF

open "$OUTPUT"
