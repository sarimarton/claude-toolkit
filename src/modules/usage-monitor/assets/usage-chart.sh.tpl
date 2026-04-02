#!/usr/bin/env bash
# usage-chart.sh — Generate an interactive HTML dashboard from Claude usage logs
#
# Supports multiple accounts: discovers all usage-*.jsonl files.
# Keyboard shortcuts toggle between accounts (←/→, h/l, 1-9).
#
# Opens the result in the default browser.

set -euo pipefail

USAGE_DIR="{{home}}/.local/share/claude-usage"
OUTPUT="/tmp/claude-usage-chart.html"

PLAN_MONTHLY_COST="{{chart_plan_cost}}"
API_COST_PER_SESSION_PCT="{{chart_api_rate}}"

export USAGE_DIR PLAN_MONTHLY_COST API_COST_PER_SESSION_PCT
python3 << 'PYEOF' > "$OUTPUT"
import json, sys, os, glob
from datetime import datetime
from collections import defaultdict

USAGE_DIR = os.environ.get("USAGE_DIR", os.path.expanduser("~/.local/share/claude-usage"))
PLAN_COST = float(os.environ.get("PLAN_MONTHLY_COST", "150"))
API_RATE = float(os.environ.get("API_COST_PER_SESSION_PCT", "0.20"))

# ── Discover all account log files ──────────────────────
log_files = {}
default_log = os.path.join(USAGE_DIR, "usage.jsonl")
if os.path.exists(default_log) and os.path.getsize(default_log) > 0:
    log_files["default"] = default_log
for f in sorted(glob.glob(os.path.join(USAGE_DIR, "usage-*.jsonl"))):
    name = os.path.basename(f).replace("usage-", "").replace(".jsonl", "")
    if os.path.getsize(f) > 0:
        log_files[name] = f

if not log_files:
    print("<html><body style='background:#1a1a2e;color:#e0e0e0;padding:40px;font-family:system-ui'><h1>No usage data found</h1><p>Looking in: " + USAGE_DIR + "</p></body></html>")
    sys.exit(0)

# ── Process each account ────────────────────────────────
def session_color(max_pct, alpha):
    if max_pct < 50: return "rgba(51, 187, 51, %s)" % alpha
    elif max_pct < 80: return "rgba(230, 179, 16, %s)" % alpha
    else: return "rgba(230, 70, 70, %s)" % alpha

def process_account(log_path):
    data = []
    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: data.append(json.loads(line))
            except: continue
    if not data: return None

    # Session series
    windows = defaultdict(list)
    for d in data:
        wid = d.get("window_id", "?")
        elapsed_h = (d["ts"] - (d["reset_ts"] - 5 * 3600)) / 3600
        windows[wid].append({"x": round(elapsed_h, 3), "y": d["pct"]})
    session_series = []
    for wid in sorted(windows.keys()):
        pts = windows[wid]
        max_pct = max(p["y"] for p in pts)
        session_series.append({"label": wid, "max_pct": max_pct, "points": pts})

    # Session datasets
    session_datasets = []
    for s in session_series:
        session_datasets.append({
            "label": s["label"], "data": s["points"],
            "borderColor": session_color(s["max_pct"], 0.5),
            "backgroundColor": "transparent", "borderWidth": 1.5,
            "pointRadius": 0, "pointHoverRadius": 4,
            "pointHoverBackgroundColor": session_color(s["max_pct"], 1.0),
            "tension": 0.2, "showLine": True,
        })

    # Timeline
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

    # Heatmap
    hour_buckets = defaultdict(list)
    for d in data:
        dt = datetime.fromtimestamp(d["ts"])
        hour_buckets[(dt.strftime("%Y-%m-%d"), dt.hour)].append(d["pct"])
    days_set = sorted(set(k[0] for k in hour_buckets.keys()))
    heatmap_data = []
    for day in days_set:
        for hour in range(24):
            vals = hour_buckets.get((day, hour), [])
            if vals:
                heatmap_data.append({"day": day, "hour": hour, "pct": round(sum(vals)/len(vals), 1)})

    # Stats
    num_measurements = len(data)
    num_windows = len(session_series)
    heavy_sessions = sum(1 for s in session_series if s["max_pct"] >= 80)
    avg_peak = round(sum(s["max_pct"] for s in session_series) / len(session_series), 1) if session_series else 0
    current_weekly = data[-1].get("weekly_pct", "N/A")
    if isinstance(current_weekly, (int, float)): current_weekly = str(current_weekly) + "%"

    # Cost
    window_max_pct = {}
    for d in data:
        wid = d.get("window_id", "?")
        month = datetime.fromtimestamp(d["ts"]).strftime("%Y-%m")
        key = (month, wid)
        if key not in window_max_pct or d["pct"] > window_max_pct[key]:
            window_max_pct[key] = d["pct"]
    monthly_stats = defaultdict(lambda: {"windows": 0, "total_pct": 0, "weekly_samples": []})
    for (month, wid), mp in window_max_pct.items():
        monthly_stats[month]["windows"] += 1
        monthly_stats[month]["total_pct"] += mp
    weekly_by_month = defaultdict(dict)
    for d in data:
        wp = d.get("weekly_pct")
        if wp is None: continue
        month = datetime.fromtimestamp(d["ts"]).strftime("%Y-%m")
        week = datetime.fromtimestamp(d["ts"]).strftime("%Y-W%W")
        weekly_by_month[month][week] = wp
    for month, weeks in weekly_by_month.items():
        monthly_stats[month]["weekly_samples"] = list(weeks.values())
    cost_rows = []
    for month in sorted(monthly_stats.keys()):
        ms = monthly_stats[month]
        wa = sum(ms["weekly_samples"]) / len(ms["weekly_samples"]) if ms["weekly_samples"] else 0
        cost_rows.append({
            "month": month, "windows": ms["windows"], "total_pct": ms["total_pct"],
            "weekly_avg": round(wa, 1),
            "sub_effective": round(PLAN_COST * wa / 100, 2),
            "api_equiv": round(ms["total_pct"] * API_RATE, 2),
        })

    return {
        "sessionDatasets": session_datasets,
        "timelineTs": timeline_ts, "timelinePct": timeline_pct,
        "timelineWeekly": timeline_weekly, "windowBoundaries": window_boundaries,
        "heatmapData": heatmap_data, "days": days_set,
        "costRows": cost_rows, "planCost": PLAN_COST, "apiRate": API_RATE,
        "numMeasurements": num_measurements, "numWindows": num_windows,
        "dateFrom": days_set[0] if days_set else "", "dateTo": days_set[-1] if days_set else "",
        "heavySessions": heavy_sessions, "avgPeak": avg_peak,
        "currentWeekly": current_weekly,
    }

all_accounts = {}
account_names = []
for name, path in log_files.items():
    result = process_account(path)
    if result:
        all_accounts[name] = result
        account_names.append(name)

if not all_accounts:
    print("<html><body style='background:#1a1a2e;color:#e0e0e0;padding:40px;font-family:system-ui'><h1>No valid data</h1></body></html>")
    sys.exit(0)

gen_time = datetime.now().strftime("%Y-%m-%d %H:%M")
multi = len(account_names) > 1

DATA_JSON = json.dumps({
    "accounts": all_accounts,
    "accountNames": account_names,
    "multi": multi,
}, separators=(",", ":"))

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
  .chart-container h2 { color: #ccc; font-size: 1.1rem; margin-bottom: 12px; font-weight: 500; }
  .chart-container .desc { color: #777; font-size: 0.8rem; margin-bottom: 16px; }
  canvas { max-height: 400px; }
  .heatmap-wrapper { overflow-x: auto; }
  #heatmapCanvas { min-width: 800px; }
  .legend { display: flex; gap: 16px; margin-top: 8px; flex-wrap: wrap; }
  .legend-item { display: flex; align-items: center; gap: 4px; font-size: 0.75rem; color: #888; }
  .legend-swatch { width: 12px; height: 12px; border-radius: 2px; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
  .stat-card { background: #16213e; border-radius: 12px; padding: 16px; }
  .stat-value { font-size: 1.8rem; font-weight: 700; color: #f0a040; }
  .stat-label { font-size: 0.8rem; color: #888; margin-top: 4px; }
  .cost-table { width: 100%; border-collapse: collapse; margin-top: 12px; }
  .cost-table th { text-align: left; color: #888; font-weight: 500; font-size: 0.8rem; padding: 6px 12px; border-bottom: 1px solid #2a2a4a; }
  .cost-table td { padding: 8px 12px; font-size: 0.9rem; border-bottom: 1px solid #1a1a2e; }
  .cost-table tr:hover td { background: #1a2540; }
  .cost-sub { color: #f0a040; }
  .cost-api { color: #508ce6; }
  .cost-note { color: #666; font-size: 0.75rem; margin-top: 12px; line-height: 1.5; }
  .cost-params { color: #555; font-size: 0.7rem; margin-top: 4px; font-family: monospace; }
  #accountIndicator {
    position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);
    font-size: 4rem; font-weight: 900; color: #f0a040;
    opacity: 0; pointer-events: none; transition: opacity 0.3s; z-index: 1000;
  }
  #accountIndicator.flash { opacity: 0.6; }
  #accountBadge {
    position: fixed; top: 16px; right: 16px;
    background: #16213e; padding: 8px 16px; border-radius: 8px;
    color: #f0a040; font-weight: 600; font-size: 0.9rem; z-index: 100;
    display: none;
  }
</style>
</head>
<body>

<div id="accountIndicator"></div>
<div id="accountBadge"></div>

<h1>&#10043; Claude Usage Dashboard</h1>
<p class="subtitle" id="subtitle"></p>

<div class="stats" id="statsCards"></div>

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
  <h2>Estimated Cost Comparison</h2>
  <p class="desc">Monthly breakdown: subscription effective value vs. estimated pay-as-you-go API equivalent.</p>
  <div style="display:flex; gap:24px; flex-wrap:wrap; margin-bottom:16px;">
    <canvas id="costChart" style="max-height:250px; flex:1; min-width:400px;"></canvas>
    <div style="flex:1; min-width:300px;">
      <table class="cost-table">
        <thead><tr><th>Month</th><th>Windows</th><th>Weekly avg</th><th class="cost-sub">Sub eff</th><th class="cost-api">API eq</th></tr></thead>
        <tbody id="costTableBody"></tbody>
      </table>
    </div>
  </div>
  <p class="cost-note">
    <strong>Sub effective</strong> = plan cost &times; avg weekly utilization.<br>
    <strong>API equiv</strong> = sum of session % consumed &times; estimated $/1% rate.
  </p>
</div>

<div class="chart-container">
  <h2>Activity Heatmap</h2>
  <p class="desc">Average session % by day and hour. Darker = higher usage.</p>
  <div class="heatmap-wrapper"><canvas id="heatmapCanvas"></canvas></div>
  <div class="legend">
    <div class="legend-item"><div class="legend-swatch" style="background:#1a1a2e"></div> 0%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#2d4a22"></div> 25%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#7a8a20"></div> 50%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#c87820"></div> 75%</div>
    <div class="legend-item"><div class="legend-swatch" style="background:#e64646"></div> 100%</div>
  </div>
</div>

<p style="text-align:center; color:#555; margin-top:16px; font-size:0.75rem;">
  Generated %%GEN_TIME%% &middot; claude-toolkit usage-chart
</p>

<script>
var _D = %%DATA_JSON%%;
Chart.defaults.color = '#888';
Chart.defaults.borderColor = '#2a2a4a';

var chartInstances = [];
var currentIdx = 0;
var names = _D.accountNames;

function destroyCharts() {
  for (var i = 0; i < chartInstances.length; i++) chartInstances[i].destroy();
  chartInstances = [];
}

function buildStats(a) {
  var el = document.getElementById('statsCards');
  el.innerHTML =
    '<div class="stat-card"><div class="stat-value">' + a.numWindows + '</div><div class="stat-label">Session windows</div></div>' +
    '<div class="stat-card"><div class="stat-value">' + a.heavySessions + '</div><div class="stat-label">Sessions 80%+</div></div>' +
    '<div class="stat-card"><div class="stat-value">' + a.avgPeak + '%</div><div class="stat-label">Avg peak</div></div>' +
    '<div class="stat-card"><div class="stat-value">' + a.currentWeekly + '</div><div class="stat-label">Weekly usage</div></div>';
}

function buildCostTable(rows) {
  var tbody = document.getElementById('costTableBody');
  tbody.innerHTML = '';
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    var tr = document.createElement('tr');
    tr.innerHTML = '<td>' + r.month + '</td><td>' + r.windows + '</td><td>' + r.weekly_avg + '%</td>' +
      '<td class="cost-sub">$' + r.sub_effective.toFixed(0) + '</td>' +
      '<td class="cost-api">$' + r.api_equiv.toFixed(0) + '</td>';
    tbody.appendChild(tr);
  }
}

var windowLinePlugin = {
  id: 'windowLines',
  _boundaries: [],
  beforeDraw: function(chart) {
    var xScale = chart.scales.x;
    var ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = 'rgba(100, 100, 150, 0.2)';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    var bounds = this._boundaries || [];
    for (var j = 0; j < bounds.length; j++) {
      var x = xScale.getPixelForValue(bounds[j]);
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

function drawHeatmap(a) {
  var canvas = document.getElementById('heatmapCanvas');
  var ctx = canvas.getContext('2d');
  var days = a.days;
  var cellW = Math.max(32, Math.floor((canvas.parentElement.clientWidth - 80) / Math.max(days.length, 1)));
  var cellH = 18, marginLeft = 40, marginTop = 24;
  canvas.width = marginLeft + days.length * cellW + 20;
  canvas.height = marginTop + 24 * cellH + 30;
  canvas.style.width = canvas.width + 'px';
  canvas.style.height = canvas.height + 'px';
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  var lookup = {};
  for (var k = 0; k < a.heatmapData.length; k++) {
    var d = a.heatmapData[k];
    lookup[d.day + ':' + d.hour] = d.pct;
  }

  ctx.fillStyle = '#666'; ctx.font = '10px system-ui'; ctx.textAlign = 'right';
  for (var h = 0; h < 24; h++) {
    if (h % 3 === 0) ctx.fillText(h + ':00', marginLeft - 4, marginTop + h * cellH + cellH * 0.7);
  }
  ctx.textAlign = 'center';
  var step = Math.max(1, Math.floor(days.length / 10));
  for (var i = 0; i < days.length; i++) {
    if (i % step === 0) ctx.fillText(days[i].slice(5), marginLeft + i * cellW + cellW / 2, marginTop - 6);
  }
  for (var di = 0; di < days.length; di++) {
    for (var h2 = 0; h2 < 24; h2++) {
      var pct = lookup[days[di] + ':' + h2];
      ctx.fillStyle = heatColor(pct);
      ctx.fillRect(marginLeft + di * cellW, marginTop + h2 * cellH, cellW - 1, cellH - 1);
      if (pct != null && cellW >= 28) {
        ctx.fillStyle = pct > 60 ? '#fff' : '#aaa';
        ctx.font = '9px system-ui'; ctx.textAlign = 'center';
        ctx.fillText(Math.round(pct) + '', marginLeft + di * cellW + cellW / 2, marginTop + h2 * cellH + cellH * 0.75);
      }
    }
  }
}

function rebuildCharts(name) {
  var a = _D.accounts[name];
  destroyCharts();

  document.getElementById('subtitle').innerHTML =
    a.numMeasurements.toLocaleString() + ' measurements &middot; ' +
    a.numWindows + ' session windows &middot; ' +
    a.dateFrom + ' &rarr; ' + a.dateTo +
    (_D.multi ? ' &middot; <strong>' + name + '</strong>' : '');

  buildStats(a);
  buildCostTable(a.costRows);

  // Session chart
  chartInstances.push(new Chart(document.getElementById('sessionChart'), {
    type: 'scatter',
    data: { datasets: a.sessionDatasets },
    options: {
      responsive: true, animation: false,
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: {
          title: function(items) { return items[0] ? items[0].dataset.label : ''; },
          label: function(item) { return item.parsed.x.toFixed(1) + 'h \u2192 ' + item.parsed.y + '% used'; }
        }}
      },
      scales: {
        x: { type: 'linear', title: { display: true, text: 'Elapsed time (hours)', color: '#888' }, min: 0, max: 5, ticks: { stepSize: 1, color: '#666' }, grid: { color: '#2a2a4a' } },
        y: { title: { display: true, text: '% used', color: '#888' }, min: 0, max: 100, ticks: { color: '#666' }, grid: { color: '#2a2a4a' } }
      }
    }
  }));

  // Timeline chart
  var tlSession = a.timelineTs.map(function(t, i) { return { x: t, y: a.timelinePct[i] }; });
  var tlWeekly = a.timelineTs.map(function(t, i) { return a.timelineWeekly[i] != null ? { x: t, y: a.timelineWeekly[i] } : null; }).filter(Boolean);
  windowLinePlugin._boundaries = a.windowBoundaries;

  chartInstances.push(new Chart(document.getElementById('timelineChart'), {
    type: 'scatter',
    data: { datasets: [
      { label: 'Session %', data: tlSession, borderColor: 'rgba(240, 160, 64, 0.7)', backgroundColor: 'transparent', borderWidth: 1.5, pointRadius: 0, pointHoverRadius: 3, showLine: true, tension: 0.1 },
      { label: 'Weekly %', data: tlWeekly, borderColor: 'rgba(80, 140, 230, 0.7)', backgroundColor: 'transparent', borderWidth: 1.5, pointRadius: 0, pointHoverRadius: 3, showLine: true, tension: 0.1 }
    ] },
    plugins: [windowLinePlugin],
    options: {
      responsive: true, animation: false,
      plugins: {
        legend: { display: true, labels: { color: '#888', usePointStyle: true, pointStyle: 'line' } },
        tooltip: { callbacks: {
          title: function(items) { return items[0] ? new Date(items[0].parsed.x).toLocaleString() : ''; },
          label: function(item) { return item.dataset.label + ': ' + item.parsed.y + '%'; }
        }}
      },
      scales: {
        x: { type: 'time', time: { unit: 'day', displayFormats: { day: 'MMM d', hour: 'MMM d HH:mm' } }, title: { display: true, text: 'Date', color: '#888' }, ticks: { color: '#666', maxTicksLimit: 15 }, grid: { color: '#2a2a4a' } },
        y: { title: { display: true, text: '% used', color: '#888' }, min: 0, max: 100, ticks: { color: '#666' }, grid: { color: '#2a2a4a' } }
      }
    }
  }));

  // Cost chart
  var months = [], subVals = [], apiVals = [];
  for (var i = 0; i < a.costRows.length; i++) {
    months.push(a.costRows[i].month);
    subVals.push(a.costRows[i].sub_effective);
    apiVals.push(a.costRows[i].api_equiv);
  }
  chartInstances.push(new Chart(document.getElementById('costChart'), {
    type: 'bar',
    data: { labels: months, datasets: [
      { label: 'Sub effective', data: subVals, backgroundColor: 'rgba(240, 160, 64, 0.7)', borderColor: 'rgba(240, 160, 64, 1)', borderWidth: 1 },
      { label: 'API equivalent', data: apiVals, backgroundColor: 'rgba(80, 140, 230, 0.7)', borderColor: 'rgba(80, 140, 230, 1)', borderWidth: 1 }
    ] },
    options: {
      responsive: true, animation: false,
      plugins: { legend: { display: true, labels: { color: '#888' } },
        tooltip: { callbacks: { label: function(item) { return item.dataset.label + ': $' + item.parsed.y.toFixed(0); } } } },
      scales: {
        x: { ticks: { color: '#666' }, grid: { color: '#2a2a4a' } },
        y: { title: { display: true, text: 'USD', color: '#888' }, ticks: { color: '#666', callback: function(v) { return '$' + v; } }, grid: { color: '#2a2a4a' } }
      }
    }
  }));

  drawHeatmap(a);
}

// ── Account switching ──────────────────────────────────
function switchAccount(idx) {
  currentIdx = idx;
  rebuildCharts(names[currentIdx]);
  if (_D.multi) {
    var ind = document.getElementById('accountIndicator');
    ind.textContent = names[currentIdx];
    ind.classList.add('flash');
    setTimeout(function() { ind.classList.remove('flash'); }, 600);
    updateBadge();
  }
}

function updateBadge() {
  var badge = document.getElementById('accountBadge');
  if (!_D.multi) { badge.style.display = 'none'; return; }
  badge.style.display = 'block';
  badge.innerHTML = '\u2190 <strong>' + names[currentIdx] + '</strong> \u2192  (' + (currentIdx + 1) + '/' + names.length + ')';
}

document.addEventListener('keydown', function(e) {
  if (!_D.multi) return;
  if (e.key === 'ArrowRight' || e.key === 'l' || e.key === ']') {
    switchAccount((currentIdx + 1) % names.length);
  } else if (e.key === 'ArrowLeft' || e.key === 'h' || e.key === '[') {
    switchAccount((currentIdx - 1 + names.length) % names.length);
  } else if (e.key >= '1' && e.key <= '9') {
    var idx = parseInt(e.key) - 1;
    if (idx < names.length) switchAccount(idx);
  }
});

// Initial render
rebuildCharts(names[0]);
updateBadge();
</script>
</body>
</html>"""

HTML = HTML.replace("%%DATA_JSON%%", DATA_JSON)
HTML = HTML.replace("%%GEN_TIME%%", gen_time)
print(HTML)
PYEOF

open "$OUTPUT"
