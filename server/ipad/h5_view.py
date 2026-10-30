"""H5 kiosk dashboard view — 1080x1920 auto-rotating, animated, live-refreshing.

Renders a single self-contained HTML document (no external CDN). The page
fetches /api/h5/state on an interval and auto-rotates through 12 screens, each
with its own bold visual treatment. Data shape comes from build_h5_state().

This module is plain Python raw strings (not f-strings), so CSS/JS braces need
no escaping. Dynamic values are injected via str.replace token substitution.
"""
from __future__ import annotations

import json


def render_h5_document(state: dict, active_screen: str, stage_w: int, stage_h: int) -> str:
    payload = json.dumps(state, ensure_ascii=False)
    active = json.dumps(active_screen, ensure_ascii=False)
    html = _HTML
    html = html.replace("/*__STAGE_W__*/0", str(stage_w))
    html = html.replace("/*__STAGE_H__*/0", str(stage_h))
    html = html.replace("\"__PAYLOAD__\"", payload)
    html = html.replace("\"__ACTIVE__\"", active)
    return html.replace("/*__CSS__*/", _CSS).replace("/*__JS__*/", _JS)


def render_h5_lite_document(state: dict, active_screen: str, stage_w: int, stage_h: int) -> str:
    payload = json.dumps(state, ensure_ascii=False)
    active = json.dumps(active_screen, ensure_ascii=False)
    html = _PHOTO_LITE_HTML
    html = html.replace("/*__STAGE_W__*/0", str(stage_w))
    html = html.replace("/*__STAGE_H__*/0", str(stage_h))
    html = html.replace("\"__PAYLOAD__\"", payload)
    html = html.replace("\"__ACTIVE__\"", active)
    return html.replace("/*__CSS__*/", _PHOTO_LITE_CSS).replace("/*__JS__*/", _PHOTO_LITE_JS)


_HTML = r"""<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#05080f">
<title>RemotePanel · H5 Kiosk</title>
<style>/*__CSS__*/</style>
</head>
<body>
<div id="fit">
  <div id="stage">
    <div class="aurora" id="aurora"></div>
    <div class="grain"></div>
    <header id="topbar">
      <div class="brand">
        <div class="logo"><span class="logodot"></span>REMOTE&nbsp;PANEL</div>
        <div class="screen-title" id="screenTitle">—</div>
        <div class="screen-sub" id="screenSub"></div>
      </div>
      <div class="clockbox">
        <div class="clock" id="clock">--:--</div>
        <div class="clock-sub" id="clockSub"></div>
      </div>
    </header>
    <main id="viewport"></main>
    <div id="progress"><div id="progressFill"></div></div>
    <nav id="dots"></nav>
    <div id="status"></div>
  </div>
</div>
<script>
window.__H5_STATE__ = "__PAYLOAD__";
window.__H5_ACTIVE__ = "__ACTIVE__";
window.__STAGE_W__ = /*__STAGE_W__*/0;
window.__STAGE_H__ = /*__STAGE_H__*/0;
</script>
<script>/*__JS__*/</script>
</body>
</html>
"""


_CSS = r"""
* { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --ink: #f7fafc;
  --muted: #93a4bc;
  --line: rgba(148,163,184,.16);
  --accent: #38bdf8;
  --accent2: #818cf8;
  --glass: rgba(13,22,38,.62);
}
html, body {
  width: 100%; height: 100%;
  background: #04070e;
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
  overflow: hidden;
  -webkit-font-smoothing: antialiased;
}
#fit {
  position: fixed; inset: 0;
  display: flex; align-items: flex-start; justify-content: center;
  background: radial-gradient(circle at 50% 0%, #0d1b30 0%, #060b16 55%, #03060d 100%);
}
#stage {
  position: relative;
  width: 1080px; height: 1920px;
  transform-origin: top center;
  overflow: hidden;
  background: linear-gradient(180deg, #070f1e 0%, #05080f 100%);
}
.aurora {
  position: absolute; inset: -20%;
  background:
    radial-gradient(40% 30% at 18% 12%, rgba(56,189,248,.30), transparent 60%),
    radial-gradient(38% 28% at 82% 18%, rgba(129,140,248,.26), transparent 60%),
    radial-gradient(50% 36% at 50% 96%, rgba(45,212,191,.20), transparent 60%);
  filter: blur(20px);
  animation: drift 26s ease-in-out infinite alternate;
  transition: opacity 1.2s ease;
  pointer-events: none;
}
@keyframes drift {
  0%   { transform: translate3d(-2%, -1%, 0) scale(1.05); }
  100% { transform: translate3d(3%, 2%, 0) scale(1.12); }
}
.grain {
  position: absolute; inset: 0; pointer-events: none; opacity: .04;
  background-image: radial-gradient(rgba(255,255,255,.7) .5px, transparent .5px);
  background-size: 4px 4px;
}

/* ---- top bar ---- */
#topbar {
  position: absolute; left: 0; right: 0; top: 0;
  display: flex; justify-content: space-between; align-items: flex-start;
  padding: 56px 64px 0; z-index: 6;
}
.brand .logo {
  display: flex; align-items: center; gap: 14px;
  font-size: 22px; font-weight: 800; letter-spacing: .42em; color: #cbd5e1;
}
.logodot {
  width: 14px; height: 14px; border-radius: 50%;
  background: var(--accent); box-shadow: 0 0 18px var(--accent);
  animation: pulse 2.4s ease-in-out infinite;
}
@keyframes pulse { 0%,100% { opacity: 1; transform: scale(1);} 50% { opacity:.5; transform: scale(.8);} }
.screen-title {
  margin-top: 18px; font-size: 76px; font-weight: 850; line-height: .98;
  letter-spacing: -.01em;
  background: linear-gradient(120deg, #fff 10%, var(--accent) 120%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
.screen-sub {
  margin-top: 8px; font-size: 26px; font-weight: 600; letter-spacing: .26em;
  text-transform: uppercase; color: var(--muted);
}
.clockbox { text-align: right; }
.clock {
  font-size: 64px; font-weight: 800; letter-spacing: .02em;
  font-variant-numeric: tabular-nums;
  text-shadow: 0 0 30px rgba(56,189,248,.25);
}
.clock-sub { margin-top: 6px; font-size: 22px; color: var(--muted); }

/* ---- viewport & screens ---- */
#viewport {
  position: absolute; left: 64px; right: 64px; top: 268px; bottom: 132px;
  z-index: 4;
}
.screen {
  position: absolute; inset: 0;
  display: grid; grid-template-columns: repeat(12, 1fr);
  grid-auto-rows: min-content; gap: 28px; align-content: start;
  opacity: 0; pointer-events: none;
  transform: translateY(40px) scale(.985);
  transition: opacity .7s cubic-bezier(.22,1,.36,1), transform .7s cubic-bezier(.22,1,.36,1);
}
.screen.active { opacity: 1; pointer-events: auto; transform: none; }
.screen.leaving { opacity: 0; transform: translateY(-30px) scale(.985); transition-duration: .5s; }

/* staggered card entrance */
.screen.active .card { animation: cardIn .7s cubic-bezier(.22,1,.36,1) backwards; }
.screen.active .card:nth-child(1) { animation-delay: .04s; }
.screen.active .card:nth-child(2) { animation-delay: .12s; }
.screen.active .card:nth-child(3) { animation-delay: .2s; }
.screen.active .card:nth-child(4) { animation-delay: .28s; }
.screen.active .card:nth-child(5) { animation-delay: .36s; }
.screen.active .card:nth-child(6) { animation-delay: .44s; }
@keyframes cardIn { from { opacity: 0; transform: translateY(26px); } to { opacity: 1; transform: none; } }

.flyin-left, .flyin-right, .flyin-up, .flyin-down, .flyin-curtain, .flyin-zoom,
.flyin-rotate-left, .flyin-rotate-right, .flyin-diag-left, .flyin-diag-right {
  opacity: 0;
  animation-duration: 1.45s;
  animation-fill-mode: both;
  animation-timing-function: cubic-bezier(.22,1,.36,1);
  will-change: transform, opacity;
}
.flyin-left { animation-name: flyInLeft; }
.flyin-right { animation-name: flyInRight; }
.flyin-up { animation-name: flyInUp; }
.flyin-down { animation-name: flyInDown; }
.flyin-curtain { animation-name: flyInCurtain; }
.flyin-zoom { animation-name: flyInZoom; }
.flyin-rotate-left { animation-name: flyInRotateLeft; transform-origin: 0% 50%; }
.flyin-rotate-right { animation-name: flyInRotateRight; transform-origin: 100% 50%; }
.flyin-diag-left { animation-name: flyInDiagLeft; }
.flyin-diag-right { animation-name: flyInDiagRight; }
.flyin-stagger-1 { animation-delay: .08s; }
.flyin-stagger-2 { animation-delay: .28s; }
.flyin-stagger-3 { animation-delay: .48s; }
.flyin-stagger-4 { animation-delay: .68s; }
.flyin-stagger-5 { animation-delay: .88s; }
.flyin-stagger-6 { animation-delay: 1.08s; }
@keyframes flyInLeft { from { opacity: 0; transform: translate3d(-140px,0,0) scale(.96); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInRight { from { opacity: 0; transform: translate3d(140px,0,0) scale(.96); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInUp { from { opacity: 0; transform: translate3d(0,120px,0) scale(.97); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInDown { from { opacity: 0; transform: translate3d(0,-120px,0) scale(.97); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInCurtain { from { opacity: 0; clip-path: inset(0 0 100% 0 round 34px); transform: translate3d(0,-70px,0) scale(1.01); } to { opacity: 1; clip-path: inset(0 0 0 0 round 34px); transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInZoom { from { opacity: 0; transform: translate3d(0,48px,0) scale(.78); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInRotateLeft { from { opacity: 0; transform: perspective(1200px) rotateY(22deg) translate3d(-110px,0,0) scale(.94); } to { opacity: 1; transform: perspective(1200px) rotateY(0deg) translate3d(0,0,0) scale(1); } }
@keyframes flyInRotateRight { from { opacity: 0; transform: perspective(1200px) rotateY(-22deg) translate3d(110px,0,0) scale(.94); } to { opacity: 1; transform: perspective(1200px) rotateY(0deg) translate3d(0,0,0) scale(1); } }
@keyframes flyInDiagLeft { from { opacity: 0; transform: translate3d(-120px,96px,0) scale(.95); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }
@keyframes flyInDiagRight { from { opacity: 0; transform: translate3d(120px,96px,0) scale(.95); } to { opacity: 1; transform: translate3d(0,0,0) scale(1); } }

/* ---- progress + dots ---- */
#progress {
  position: absolute; left: 0; right: 0; bottom: 0; height: 6px;
  background: rgba(148,163,184,.12); z-index: 7;
}
#progressFill {
  height: 100%; width: 0%;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  box-shadow: 0 0 18px var(--accent);
}
#dots {
  position: absolute; left: 0; right: 0; bottom: 40px; z-index: 7;
  display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; padding: 0 64px;
}
#dots .dot {
  width: 12px; height: 12px; border-radius: 50%;
  background: rgba(148,163,184,.28); transition: all .4s ease;
}
#dots .dot.active {
  width: 40px; border-radius: 999px;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  box-shadow: 0 0 16px var(--accent);
}
#status {
  position: absolute; right: 64px; bottom: 38px; z-index: 7;
  font-size: 18px; color: var(--muted); display: flex; align-items: center; gap: 10px;
}
#status .live {
  width: 9px; height: 9px; border-radius: 50%; background: #22c55e;
  box-shadow: 0 0 12px #22c55e; animation: pulse 2s infinite;
}
#status.stale .live { background: #f59e0b; box-shadow: 0 0 12px #f59e0b; }



/* ---- card system ---- */
.card {
  position: relative;
  border-radius: 34px;
  background: var(--glass);
  border: 1px solid var(--line);
  padding: 34px 36px;
  overflow: hidden;
  backdrop-filter: blur(22px);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.05), 0 30px 60px rgba(0,0,0,.32);
}
.card::before {
  content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 5px;
  background: linear-gradient(180deg, var(--accent), var(--accent2));
  opacity: .9;
}
.card h3 {
  font-size: 22px; font-weight: 700; letter-spacing: .18em; text-transform: uppercase;
  color: #bcd2f0; margin-bottom: 22px; display: flex; align-items: center; gap: 12px;
}
.card h3 .ic { font-size: 26px; }
.span12 { grid-column: span 12; }
.span8  { grid-column: span 8; }
.span7  { grid-column: span 7; }
.span6  { grid-column: span 6; }
.span5  { grid-column: span 5; }
.span4  { grid-column: span 4; }

/* big numerics */
.hero-num {
  font-size: 200px; font-weight: 850; line-height: .82; letter-spacing: -.03em;
  font-variant-numeric: tabular-nums;
}
.hero-unit { font-size: 64px; font-weight: 700; color: var(--muted); }
.big-copy { font-size: 56px; font-weight: 800; line-height: 1.08; letter-spacing: -.01em; }
.mid-copy { font-size: 34px; font-weight: 600; line-height: 1.32; color: #dbe6f5; }
.sub { font-size: 26px; color: var(--muted); line-height: 1.45; }

/* stat tiles */
.stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
.stat {
  padding: 24px; border-radius: 24px;
  background: rgba(255,255,255,.04); border: 1px solid rgba(148,163,184,.12);
}
.stat .label { font-size: 18px; letter-spacing: .12em; text-transform: uppercase; color: #8fb6e6; }
.stat .value { margin-top: 12px; font-size: 52px; font-weight: 800; font-variant-numeric: tabular-nums; }

/* lists */
.list { display: flex; flex-direction: column; gap: 16px; }
.row {
  display: flex; gap: 18px; align-items: flex-start;
  padding: 20px 22px; border-radius: 22px;
  background: rgba(255,255,255,.035); border: 1px solid rgba(148,163,184,.1);
}
.row .idx {
  font-size: 30px; font-weight: 850; color: var(--accent);
  min-width: 48px; font-variant-numeric: tabular-nums;
}
.row .body { flex: 1; min-width: 0; }
.row .title { font-size: 30px; font-weight: 650; line-height: 1.25; }
.row .meta { margin-top: 6px; font-size: 22px; color: var(--muted); }
.clamp2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.clamp3 { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }

/* chips */
.chips { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 22px; }
.chip {
  padding: 12px 20px; border-radius: 999px; font-size: 22px;
  background: rgba(56,189,248,.14); color: #dcefff; border: 1px solid rgba(125,211,252,.28);
}

/* messages */
.msg { padding: 22px 24px; border-radius: 24px; background: rgba(255,255,255,.04);
  border: 1px solid rgba(148,163,184,.1); }
.msg + .msg { margin-top: 16px; }
.msg.user { background: linear-gradient(120deg, rgba(56,189,248,.16), rgba(129,140,248,.12)); }
.msg .who { font-size: 20px; font-weight: 700; letter-spacing: .1em; color: #9fd0ff; }
.msg.user .who { color: #fbcfe8; }
.msg .txt { margin-top: 12px; font-size: 28px; line-height: 1.42; color: #e7eefb; }

/* media */
.poster-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 22px; }
.movies-grid { gap: 18px; }
.poster {
  border-radius: 22px; overflow: hidden; background: #0c1422;
  border: 1px solid rgba(148,163,184,.12);
}
.poster img { width: 100%; aspect-ratio: 2/3; object-fit: cover; display: block; }
.poster .cap { padding: 16px 18px; }
.poster .cap .t { font-size: 24px; font-weight: 700; line-height: 1.2; }
.poster .cap .d { margin-top: 6px; font-size: 18px; color: var(--muted); }
.game {
  display: flex; gap: 22px; align-items: center; padding: 18px; border-radius: 24px;
  background: rgba(255,255,255,.035); border: 1px solid rgba(148,163,184,.1);
}
.steam-list { gap: 12px; }
.steam-game { padding: 14px 16px; border-radius: 20px; }
.steam-game img { width: 220px; height: 104px; border-radius: 14px; }
.steam-game .gt { font-size: 27px; line-height: 1.12; }
.steam-game .gs { margin-top: 6px; font-size: 20px; line-height: 1.28; }
.game img { width: 260px; height: 122px; object-fit: cover; border-radius: 16px; background: #0c1422; }
.game .gi { flex: 1; min-width: 0; }
.game .gt { font-size: 30px; font-weight: 700; }
.game .gs { margin-top: 8px; font-size: 22px; color: var(--muted); }

/* ring gauge */
.ring-row { display: flex; gap: 28px; align-items: center; flex-wrap: wrap; }
.ring { position: relative; width: 220px; height: 220px; }
.ring svg { transform: rotate(-90deg); }
.ring .rc { font-size: 56px; font-weight: 850; position: absolute; inset: 0;
  display: flex; align-items: center; justify-content: center; flex-direction: column; }
.ring .rc small { font-size: 22px; color: var(--muted); font-weight: 600; }

/* bars */
.bar { height: 20px; border-radius: 999px; background: rgba(148,163,184,.16); overflow: hidden; }
.bar > span { display: block; height: 100%; border-radius: 999px;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  width: 0%; transition: width 1.1s cubic-bezier(.22,1,.36,1); }

.center-col { display: flex; flex-direction: column; justify-content: center; height: 100%; }
.weather-glyph { font-size: 220px; line-height: 1; filter: drop-shadow(0 0 30px rgba(56,189,248,.4)); }
"""


_JS = r"""
'use strict';
(function () {
  var state = window.__H5_STATE__ || {};
  var STAGE_W = window.__STAGE_W__ || 1080;
  var STAGE_H = window.__STAGE_H__ || 1920;

  // ---- helpers ----
  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
  function el(id) { return document.getElementById(id); }
  function num(v, d) { var n = Number(v); return isFinite(n) ? n : (d == null ? 0 : d); }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  // ---- fit stage into viewport ----
  // Always fill width: scale by viewport width. If the device is shorter than
  // 9:16 the bottom overflows (clipped); if taller, the gap sits below.
  function fit() {
    var s = window.innerWidth / STAGE_W;
    el('stage').style.transform = 'translateX(-50%) scale(' + s + ')';
    el('stage').style.left = '50%';
  }
  window.addEventListener('resize', fit);

  // ---- clock ----
  function tickClock() {
    var d = new Date();
    var hh = String(d.getHours()).padStart(2, '0');
    var mm = String(d.getMinutes()).padStart(2, '0');
    var ss = String(d.getSeconds()).padStart(2, '0');
    el('clock').innerHTML = hh + ':' + mm + '<span style="font-size:32px;color:var(--muted)">:' + ss + '</span>';
    var wk = ['周日','周一','周二','周三','周四','周五','周六'][d.getDay()];
    el('clockSub').textContent = (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + wk;
  }

  // ---- animated number count-up ----
  function animateNumbers(root) {
    var nodes = root.querySelectorAll('[data-count]');
    nodes.forEach(function (node) {
      var target = num(node.getAttribute('data-count'), 0);
      var dec = num(node.getAttribute('data-dec'), 0);
      var dur = 900, start = performance.now();
      function step(now) {
        var p = clamp((now - start) / dur, 0, 1);
        var eased = 1 - Math.pow(1 - p, 3);
        node.textContent = (target * eased).toFixed(dec);
        if (p < 1) requestAnimationFrame(step);
        else node.textContent = target.toFixed(dec);
      }
      requestAnimationFrame(step);
    });
  }
  function animateBars(root) {
    root.querySelectorAll('.bar > span[data-w]').forEach(function (s) {
      var w = clamp(num(s.getAttribute('data-w'), 0), 0, 100);
      requestAnimationFrame(function () { setTimeout(function () { s.style.width = w + '%'; }, 60); });
    });
  }
  function animateRings(root) {
    root.querySelectorAll('circle[data-ring]').forEach(function (c) {
      var pct = clamp(num(c.getAttribute('data-ring'), 0), 0, 100);
      var r = num(c.getAttribute('r'), 90);
      var circ = 2 * Math.PI * r;
      c.style.strokeDasharray = circ;
      c.style.strokeDashoffset = circ;
      requestAnimationFrame(function () {
        setTimeout(function () {
          c.style.transition = 'stroke-dashoffset 1.2s cubic-bezier(.22,1,.36,1)';
          c.style.strokeDashoffset = circ * (1 - pct / 100);
        }, 80);
      });
    });
  }

  // SVG ring helper
  function ring(pct, label, unit, color) {
    pct = clamp(num(pct, 0), 0, 100);
    var r = 90, c = 2 * Math.PI * r;
    return '<div class="ring"><svg width="220" height="220" viewBox="0 0 220 220">' +
      '<circle cx="110" cy="110" r="' + r + '" fill="none" stroke="rgba(148,163,184,.16)" stroke-width="18"/>' +
      '<circle data-ring="' + pct + '" cx="110" cy="110" r="' + r + '" fill="none" stroke="' + color + '" stroke-width="18" stroke-linecap="round" style="stroke-dasharray:' + c + ';stroke-dashoffset:' + c + '"/>' +
      '</svg><div class="rc"><span data-count="' + pct + '">0</span><small>' + esc(label) + (unit || '') + '</small></div></div>';
  }

  // ---- shared list builders ----
  function headlineList(lines, max) {
    lines = (lines || []).slice(0, max || 5);
    if (!lines.length) return '<div class="sub">暂无内容</div>';
    return '<div class="list">' + lines.map(function (line, i) {
      return '<div class="row"><div class="idx">' + String(i + 1).padStart(2, '0') + '</div>' +
        '<div class="body"><div class="title clamp2">' + esc(line) + '</div></div></div>';
    }).join('') + '</div>';
  }
  function msgList(items, max) {
    items = (items || []).slice(-(max || 4));
    if (!items.length) return '<div class="sub">暂无对话</div>';
    return items.map(function (m) {
      var isUser = m.role === 'user';
      return '<div class="msg ' + (isUser ? 'user' : '') + '"><div class="who">' +
        (isUser ? '主人' : 'HERMES') + '</div><div class="txt clamp3">' + esc(m.content) + '</div></div>';
    }).join('');
  }

  // ---- per-screen renderers (each returns inner HTML for #viewport) ----
  var SCREENS = {
    'work-cockpit': function () {
      var w = state.work || {}, d = state.daily || {}, dev = state.device || {};
      var topics = (d.news_topics || []).slice(0, 6);
      return card('span8 flyin-curtain flyin-stagger-1', '🎯', '当前任务',
          '<div class="big-copy">' + esc(w.current_task || '等待任务') + '</div>' +
          '<div class="sub" style="margin-top:18px">' + esc(w.summary || '') + '</div>' +
          (topics.length ? '<div class="chips">' + topics.map(function (t) { return '<span class="chip">' + esc(t) + '</span>'; }).join('') + '</div>' : '')) +
        card('span4 flyin-right flyin-stagger-2', '⚡', '状态',
          '<div class="stat-grid" style="grid-template-columns:1fr">' +
          stat('下一步', (w.next_task || '—')) +
          stat('模式', state.mode === 'rotate' ? '轮播' : '固定') +
          stat('在线', dev.device_online ? 'YES' : 'NO') + '</div>') +
        card('span12 flyin-up flyin-stagger-3', '💬', '最近对话', msgList((state.session || {}).recent_messages, 3));
    },
    'chat-stream': function () {
      var s = state.session || {};
      return card('span12 flyin-down flyin-stagger-1', '🗨️', s.title || 'Hermes 对话', msgList(s.recent_messages, 5)) +
        card('span12 flyin-diag-right flyin-stagger-2', '📝', '会话摘要', '<div class="mid-copy">' + esc(s.summary || '暂无摘要') + '</div>');
    },
    'alerts': function () {
      var alerts = state.alerts || [];
      var sevColor = { info: '#38bdf8', warn: '#f59e0b', error: '#ef4444', critical: '#ef4444' };
      var w = state.work || {};
      var top = card('span4 flyin-zoom flyin-stagger-1', '🔔', '告警总览',
        '<div><span class="hero-num" data-count="' + alerts.length + '" data-dec="0" style="font-size:140px">0</span></div>' +
        '<div class="sub" style="margin-top:12px">当前待关注事项</div>' +
        '<div class="chips" style="margin-top:18px">' +
        '<span class="chip">Inbox</span><span class="chip">Live</span><span class="chip">Priority</span></div>');
      var side = card('span8 flyin-right flyin-stagger-2', '🧭', '处理建议',
        '<div class="big-copy" style="font-size:48px">' + esc(w.next_task || '继续当前优先事项') + '</div>' +
        '<div class="sub" style="margin-top:18px">' + esc(w.summary || '暂无附加说明') + '</div>');
      var body = alerts.length ? '<div class="list">' + alerts.map(function (a, idx) {
        var col = sevColor[a.severity] || '#38bdf8';
        return '<div class="row flyin-' + (idx % 2 === 0 ? 'left' : 'right') + ' flyin-stagger-' + Math.min(idx + 1, 6) + '" style="border-left:6px solid ' + col + '">' +
          '<div class="body"><div class="title">' + esc(a.title || '提醒') + '</div>' +
          '<div class="meta">' + esc(a.body || '') + '</div></div>' +
          '<span class="chip" style="background:' + col + '22;border-color:' + col + '66;color:#fff">' + esc(a.severity || 'info') + '</span></div>';
      }).join('') + '</div>' : '<div class="sub">暂无提醒</div>';
      return top + side + card('span12 flyin-up flyin-stagger-3', '📋', '提醒列表', body);
    },
    'weather-today': function () {
      var w = state.weather || {};
      return card('span7 center-col flyin-left flyin-stagger-1', '', '',
          '<div class="weather-glyph">' + esc(w.icon || '☁') + '</div>' +
          '<div class="screen-sub" style="margin-top:10px">' + esc(w.city || 'Shanghai') + '</div>') +
        card('span5 center-col flyin-up flyin-stagger-2', '', '',
          '<div><span class="hero-num" data-count="' + num(w.temperature, 0) + '" data-dec="1">0</span><span class="hero-unit">°C</span></div>' +
          '<div class="mid-copy" style="margin-top:18px">' + esc(w.description || '天气') + '</div>' +
          '<div class="stat-grid" style="margin-top:26px">' +
          stat('最低', (w.temp_min != null ? w.temp_min + '°' : '--')) +
          stat('最高', (w.temp_max != null ? w.temp_max + '°' : '--')) +
          stat('风速', (w.wind_speed != null ? w.wind_speed : '--')) + '</div>');
    },
    'weather-weekly': function () {
      var days = (state.weather || {}).weekly || [];
      var body = days.length ? '<div class="list">' + days.map(function (it, idx) {
        var lo = num(it.temp_min, 0), hi = num(it.temp_max, 0);
        var w = clamp((hi - lo) * 4 + 20, 12, 100);
        return '<div class="row flyin-right flyin-stagger-' + Math.min(idx + 1, 6) + '"><div class="idx" style="min-width:120px;color:var(--ink);font-size:26px">' + esc(it.weekday) + '</div>' +
          '<div class="body"><div style="display:flex;align-items:center;gap:18px">' +
          '<span style="font-size:30px">' + esc(it.icon || '☁') + '</span>' +
          '<div class="bar" style="flex:1"><span data-w="' + w + '"></span></div>' +
          '<span style="font-size:26px;font-variant-numeric:tabular-nums">' + lo + '° / ' + hi + '°</span></div>' +
          '<div class="meta">' + esc(it.description) + '</div></div></div>';
      }).join('') + '</div>' : '<div class="sub">暂无周预报</div>';
      return card('span12 flyin-curtain flyin-stagger-1', '📅', '一周趋势 · 7-Day', body);
    },
    'system': function () {
      var o = state.ops || {}, v = state.vps || {};
      return card('span6 flyin-curtain flyin-stagger-1', '🖥️', '系统负载',
          '<div class="ring-row">' +
          ring(o.cpu_pct, 'CPU', '%', '#34d399') +
          ring(o.mem_pct, 'MEM', '%', '#38bdf8') +
          ring(o.disk_pct, 'DISK', '%', '#a78bfa') + '</div>' +
          '<div class="sub" style="margin-top:22px">' + esc(o.host || '') + ' · ' + esc(o.os || '') + ' · 热状态 ' + esc(o.thermal_status || '未知') + '</div>') +
        card('span6 flyin-diag-right flyin-stagger-2', '🌐', 'VPS 流量',
          '<div><span class="hero-num" data-count="' + num(v.percent, 0) + '" data-dec="1" style="font-size:120px">0</span><span class="hero-unit">%</span></div>' +
          '<div class="bar" style="margin:20px 0"><span data-w="' + num(v.percent, 0) + '"></span></div>' +
          '<div class="stat-grid">' +
          stat('已用', esc(v.used || '--')) +
          stat('剩余', esc(v.remain || '--')) +
          stat('内存', (o.memory_used_gb != null ? o.memory_used_gb + 'G' : '--')) + '</div>' +
          '<div class="sub" style="margin-top:18px">' + esc(v.cycle || '') + '</div>');
    },
    'traffic': function () {
      var o = state.ops || {}, v = state.vps || {};
      var lines = o.traffic_lines || [];
      var top = card('span5 center-col flyin-left flyin-stagger-1', '', '',
          '<div class="screen-sub">月度用量</div>' +
          '<div><span class="hero-num" data-count="' + num(v.percent, 0) + '" data-dec="1" style="font-size:150px">0</span><span class="hero-unit">%</span></div>' +
          '<div class="bar" style="margin-top:24px"><span data-w="' + num(v.percent, 0) + '"></span></div>') +
        card('span7 flyin-right flyin-stagger-2', '📡', '链路明细', lines.length ?
          '<div class="list">' + lines.map(function (l) { return '<div class="row"><div class="body"><div class="title">' + esc(l) + '</div></div></div>'; }).join('') + '</div>'
          : '<div class="sub">暂无数据</div>');
      var bottom = card('span12 flyin-up flyin-stagger-3', '🌐', '带宽面板',
          '<div class="stat-grid">' +
          stat('已用', esc(v.used || '--')) +
          stat('剩余', esc(v.remain || '--')) +
          stat('占比', (v.percent != null ? Number(v.percent).toFixed(1) + '%' : '--')) + '</div>' +
          '<div class="sub" style="margin-top:18px">计费周期：' + esc(v.cycle || '暂无') + '</div>');
      return top + bottom;
    },
    'news': function () {
      var n = state.news || {};
      var d = state.daily || {};
      var top = card('span7 flyin-left flyin-stagger-1', '📰', 'Solidot 要闻', headlineList(n.daily, 5)) +
        card('span5 flyin-up flyin-stagger-2', '🐙', 'HelloGitHub', headlineList(n.hello, 5));
      var bottom = card('span12 flyin-up flyin-stagger-3', '✍️', 'Daily Focus',
        '<div class="big-copy" style="font-size:46px">' + esc(d.quote || '今日继续推进。') + '</div>' +
        '<div class="chips" style="margin-top:18px">' + (d.news_topics || []).slice(0,6).map(function(t){ return '<span class="chip">' + esc(t) + '</span>'; }).join('') + '</div>');
      return top + bottom;
    },
    'github': function () {
      var n = state.news || {};
      var list = (n.github || []).slice(0, 8);
      var primary = card('span8 flyin-curtain flyin-stagger-1', '⚙️', 'GitHub Changelog',
        (list.length ? '<div class="list">' + list.slice(0,5).map(function (line, idx) {
          return '<div class="row flyin-up flyin-stagger-' + Math.min(idx + 1, 5) + '"><div class="idx">' + String(idx + 1).padStart(2, '0') + '</div><div class="body"><div class="title clamp2">' + esc(line) + '</div></div></div>';
        }).join('') + '</div>' : '<div class="sub">暂无 GitHub 动态</div>'));
      var side = card('span4 flyin-diag-right flyin-stagger-2', '🧩', 'Highlights',
        '<div class="chips">' + list.slice(0,3).map(function(line){ return '<span class="chip">' + esc(line.slice(0, 22)) + '</span>'; }).join('') + '</div>' +
        '<div class="stat-grid" style="grid-template-columns:1fr;margin-top:20px">' + stat('条目', String(list.length)) + stat('来源', 'GitHub') + '</div>');
      var extra = card('span12 flyin-up flyin-stagger-3', '📝', 'More Updates',
        (list.length > 5 ? '<div class="list">' + list.slice(5,8).map(function (line, idx) {
          return '<div class="row"><div class="idx">' + String(idx + 6).padStart(2, '0') + '</div><div class="body"><div class="title clamp2">' + esc(line) + '</div></div></div>';
        }).join('') + '</div>' : '<div class="sub">更多更新稍后同步</div>'));
      return primary + side + extra;
    },
    'steam': function () {
      var s = state.steam || {};
      var items = (s.new_releases || []).concat(s.top_sellers || []).slice(0, 7);
      var body = items.length ? '<div class="list steam-list">' + items.map(function (g, idx) {
        var img = g.header_url || g.capsule_url || '';
        return '<div class="game steam-game flyin-' + (idx === 0 ? 'left' : 'up') + ' flyin-stagger-' + Math.min(idx + 1, 6) + '">' + (img ? '<img src="' + esc(img) + '" alt="">' : '') +
          '<div class="gi"><div class="gt clamp2">' + esc(g.title) + '</div>' +
          '<div class="gs clamp2">' + esc(g.subtitle || g.summary || '') + '</div></div></div>';
      }).join('') + '</div>' : '<div class="sub">暂无游戏数据</div>';
      return card('span12 flyin-curtain flyin-stagger-1', '🎮', 'Steam 新游 & 热销', body);
    },
    'movies': function () {
      var items = (state.movies || []).slice(0, 8);
      var lead = items[0] || {};
      var wall = items.length ? '<div class="poster-grid movies-grid">' + items.slice(0, 6).map(function (m, idx) {
        return '<div class="poster flyin-zoom flyin-stagger-' + Math.min(idx + 1, 6) + '">' + (m.poster_url ? '<img src="' + esc(m.poster_url) + '" alt="">' : '<div style="aspect-ratio:2/3"></div>') +
          '<div class="cap"><div class="t clamp2">' + esc(m.title) + '</div><div class="d">' + esc(m.release_date) + '</div></div></div>';
      }).join('') + '</div>' : '<div class="sub">暂无影讯</div>';
      var bottom = card('span12 flyin-up flyin-stagger-3', '🎞️', 'Cinema Focus',
        '<div class="big-copy" style="font-size:46px">' + esc(lead.title || '本周焦点') + '</div>' +
        '<div class="sub" style="margin-top:12px">上映 ' + esc(lead.release_date || '暂无日期') + '</div>' +
        '<div class="chips" style="margin-top:18px">' + items.slice(6,8).map(function(m){ return '<span class="chip">' + esc(m.title || 'Coming Soon') + '</span>'; }).join('') + '</div>');
      return card('span12 flyin-rotate-left flyin-stagger-1', '🎬', '正在热映 · Now Playing', wall) + bottom;
    },
    'print-ops': function () {
      var p = (state.print || {}).primary || {};
      var temps = p.temps || {};
      var ams = (p.ams || []).flatMap(function (u) {
        return (u.slots || []).map(function (sl) {
          var b = sl.bound || {};
          return { name: b.name || sl.type || 'Slot', pct: num(b.remainingPercent != null ? b.remainingPercent : sl.remainPercent, 0) };
        });
      }).slice(0, 8);
      var amsBody = ams.length ? ams.map(function (a) {
        return '<div class="row"><div class="body"><div class="title">' + esc(a.name) + '</div>' +
          '<div class="bar" style="margin-top:10px"><span data-w="' + a.pct + '"></span></div></div>' +
          '<span class="idx" style="color:var(--ink)">' + Math.round(a.pct) + '%</span></div>';
      }).join('') : '<div class="sub">无料仓数据</div>';
      return card('span6 flyin-curtain flyin-stagger-1', '🖨️', '打印进度',
          '<div class="ring-row">' + ring(p.progress, '完成', '%', '#38bdf8') +
          '<div><div class="big-copy">' + esc(p.statusText || p.status || 'IDLE') + '</div>' +
          '<div class="sub" style="margin-top:12px">' + esc(p.name || p.model || 'Printer') + '</div>' +
          '<div class="sub">' + esc(p.fileName || '暂无任务') + '</div></div></div>' +
          '<div class="stat-grid" style="margin-top:24px">' +
          stat('喷嘴', (temps.nozzle != null ? temps.nozzle + '°' : '--')) +
          stat('热床', (temps.bed != null ? temps.bed + '°' : '--')) +
          stat('剩余', (p.remainingMinutes != null ? p.remainingMinutes + 'm' : '--')) + '</div>') +
        card('span6 flyin-up flyin-stagger-2', '🧵', 'AMS 料仓', '<div class="list">' + amsBody + '</div>');
    }
  };

  // ---- card + stat helpers ----
  function card(cls, ic, title, body) {
    var head = title ? '<h3>' + (ic ? '<span class="ic">' + ic + '</span>' : '') + esc(title) + '</h3>' : '';
    return '<section class="card ' + cls + '">' + head + body + '</section>';
  }
  function stat(label, value) {
    return '<div class="stat"><div class="label">' + esc(label) + '</div><div class="value">' + esc(value) + '</div></div>';
  }

  // ---- rotation + live refresh engine ----
  var order = (state.screens || []).map(function (s) { return s.id; });
  if (!order.length) order = Object.keys(SCREENS);
  var byId = {};
  (state.screens || []).forEach(function (s) { byId[s.id] = s; });

  var idx = Math.max(0, order.indexOf(window.__H5_ACTIVE__));
  if (idx < 0) idx = 0;
  var dwell = clamp(num((state.template || {}).dwell_seconds, 12), 6, 60) * 1000;
  var paused = false, pauseTimer = null, progStart = 0, rafId = null;

  function applyAccent(meta) {
    var root = document.documentElement.style;
    root.setProperty('--accent', (meta && meta.accent) || '#38bdf8');
    root.setProperty('--accent2', (meta && meta.accent2) || '#818cf8');
  }

  function show(i, dir) {
    idx = (i + order.length) % order.length;
    var id = order[idx];
    var meta = byId[id] || {};
    applyAccent(meta);
    el('screenTitle').textContent = meta.title || id;
    el('screenSub').textContent = meta.subtitle || '';

    var vp = el('viewport');
    var prev = vp.querySelector('.screen.active');
    if (prev) { prev.classList.remove('active'); prev.classList.add('leaving');
      setTimeout(function () { if (prev.parentNode) prev.parentNode.removeChild(prev); }, 520); }

    var fn = SCREENS[id] || function () { return '<div class="sub">空白屏</div>'; };
    var div = document.createElement('div');
    div.className = 'screen';
    div.innerHTML = fn();
    vp.appendChild(div);
    // force reflow then activate for transition
    void div.offsetWidth;
    div.classList.add('active');
    animateNumbers(div); animateBars(div); animateRings(div);

    renderDots();
    resetProgress();
  }

  function settleEntranceAnimations(root) {
    if (!root) return;
    var nodes = root.querySelectorAll('.flyin-left, .flyin-right, .flyin-up, .flyin-down, .flyin-curtain, .flyin-zoom, .flyin-rotate-left, .flyin-rotate-right, .flyin-diag-left, .flyin-diag-right');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].style.animation = 'none';
      nodes[i].style.opacity = '1';
      nodes[i].style.transform = 'translate3d(0,0,0) scale(1) rotate(0deg)';
      nodes[i].style.clipPath = 'inset(0 0 0 0 round 34px)';
    }
  }

  function renderDots() {
    el('dots').innerHTML = order.map(function (id, i) {
      return '<span class="dot ' + (i === idx ? 'active' : '') + '"></span>';
    }).join('');
  }

  function resetProgress() {
    progStart = performance.now();
    if (rafId) cancelAnimationFrame(rafId);
    function loop(now) {
      if (!paused) {
        var p = clamp((now - progStart) / dwell, 0, 1);
        el('progressFill').style.width = (p * 100) + '%';
        if (p >= 1) { next(); return; }
      } else { progStart = now - 0; }
      rafId = requestAnimationFrame(loop);
    }
    rafId = requestAnimationFrame(loop);
  }
  function next() { show(idx + 1); }
  function prev() { show(idx - 1); }

  function pauseAwhile() {
    paused = true;
    if (pauseTimer) clearTimeout(pauseTimer);
    pauseTimer = setTimeout(function () { paused = false; progStart = performance.now(); }, 12000);
  }

  // touch / click interaction: tap right half = next, left half = prev
  el('stage').addEventListener('click', function (ev) {
    pauseAwhile();
    var x = ev.clientX;
    if (x > window.innerWidth / 2) next(); else prev();
  });
  var touchX = 0;
  el('stage').addEventListener('touchstart', function (e) { touchX = e.touches[0].clientX; }, { passive: true });
  el('stage').addEventListener('touchend', function (e) {
    var dx = e.changedTouches[0].clientX - touchX;
    if (Math.abs(dx) > 60) { pauseAwhile(); if (dx < 0) next(); else prev(); }
  }, { passive: true });

  // ---- live data refresh ----
  function setStatus(stale) {
    var s = el('status');
    s.className = stale ? 'stale' : '';
    s.innerHTML = '<span class="live"></span>' + (stale ? '数据延迟' : '实时');
  }
  function refresh() {
    fetch('/api/h5/state', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (!data || !data.screens) return;
        state = data;
        byId = {};
        (state.screens || []).forEach(function (s) { byId[s.id] = s; });
        order = (state.screens || []).map(function (s) { return s.id; });
        dwell = clamp(num((state.template || {}).dwell_seconds, 12), 6, 60) * 1000;
        // re-render current screen in place with fresh data
        var vp = el('viewport');
        var cur = vp.querySelector('.screen.active');
        var fn = SCREENS[order[idx]];
        if (cur && fn) {
          cur.innerHTML = fn();
          animateNumbers(cur); animateBars(cur); animateRings(cur);
          settleEntranceAnimations(cur);
        }
        setStatus(false);
      })
      .catch(function () { setStatus(true); });
  }

  // ---- boot ----
  fit();
  tickClock();
  setInterval(tickClock, 1000);
  setStatus(false);
  show(idx);
  setInterval(refresh, 30000);

})();
"""


_PHOTO_LITE_HTML = r"""<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#03060b"><title>每日照片</title><style>/*__CSS__*/</style></head>
<body><div id="fit"><main id="stage"><img id="current" alt=""><img id="incoming" alt=""><div id="empty">正在准备今日照片</div><div id="counter"></div><div id="progress"><i></i></div></main></div>
<script>window.__H5_STATE__="__PAYLOAD__";window.__H5_ACTIVE__="__ACTIVE__";window.__STAGE_W__=/*__STAGE_W__*/0;window.__STAGE_H__=/*__STAGE_H__*/0;</script><script>/*__JS__*/</script></body></html>"""

_PHOTO_LITE_CSS = r"""
*{box-sizing:border-box;margin:0;padding:0}html,body{width:100%;height:100%;overflow:hidden;background:#03060b;color:#fff}#fit{position:fixed;inset:0;background:#03060b;overflow:hidden}#stage{position:absolute;left:50%;top:0;width:1080px;height:1800px;transform-origin:top center;overflow:hidden;background:#05070b}#current,#incoming{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;transition:opacity .75s ease}#current{opacity:1;z-index:1}#incoming{opacity:0;z-index:2}#incoming.show{opacity:1}#empty{display:none;position:absolute;inset:0;align-items:center;justify-content:center;font:800 58px -apple-system,"PingFang SC",sans-serif}#counter{position:absolute;z-index:5;left:50%;bottom:24px;transform:translateX(-50%);padding:7px 14px 6px;border-radius:999px;background:rgba(3,6,11,.62);font:22px -apple-system,sans-serif;letter-spacing:.16em;color:rgba(255,255,255,.82);text-shadow:0 2px 8px #000}#progress{position:absolute;z-index:6;left:0;right:0;bottom:0;height:7px;background:rgba(255,255,255,.16)}#progress i{display:block;width:0;height:100%;background:#fff}
"""

_PHOTO_LITE_JS = r"""
'use strict';(function(){var state=window.__H5_STATE__||{},gallery=state.photo_gallery||{},items=gallery.items||[],batchKey=String(gallery.date||'')+'|'+String(gallery.created_at||'')+'|'+String(gallery.editorial_updated_at||''),stage=document.getElementById('stage'),current=document.getElementById('current'),incoming=document.getElementById('incoming'),empty=document.getElementById('empty'),counter=document.getElementById('counter'),bar=document.querySelector('#progress i'),W=window.__STAGE_W__||1080,H=window.__STAGE_H__||1800,idx=-1,timer=null,busy=false,dwell=Math.max(8000,Number((state.template||{}).dwell_seconds||20)*1000);
function fit(){var s=Math.min(innerWidth/W,innerHeight/H);stage.style.width=W+'px';stage.style.height=H+'px';stage.style.transform='translateX(-50%) scale('+s+')'}
function url(n){return '/h5-photo-frame.jpg?index='+n+'&batch='+encodeURIComponent(batchKey)}
function preload(n){if(!items.length)return;var p=new Image();p.src=url((n+items.length)%items.length)}
function progress(){bar.style.transition='none';bar.style.width='0';requestAnimationFrame(function(){requestAnimationFrame(function(){bar.style.transition='width '+dwell+'ms linear';bar.style.width='100%'})})}
function show(n,instant){if(!items.length){empty.style.display='flex';return}if(busy)return;n=(n+items.length)%items.length;busy=true;var target=incoming,source=url(n);target.classList.remove('show');target.onload=function(){var ready=target.decode?target.decode():Promise.resolve();ready.then(function(){if(target!==incoming||target.getAttribute('src')!==source)return;empty.style.display='none';idx=n;counter.textContent=String(idx+1).padStart(2,'0')+' / '+String(items.length).padStart(2,'0');target.classList.add('show');setTimeout(function(){if(target!==incoming)return;var previous=current;current=target;incoming=previous;current.id='current';incoming.id='incoming';current.classList.remove('show');incoming.classList.remove('show');incoming.onload=null;incoming.onerror=null;busy=false;progress();clearTimeout(timer);timer=setTimeout(function(){show(idx+1,false)},dwell);preload(idx+1)},instant?0:780)}).catch(function(){target.onerror()})};target.onerror=function(){if(target!==incoming)return;busy=false;clearTimeout(timer);timer=setTimeout(function(){show(n,false)},2000)};target.src=source}
function applyGallery(next){if(!next||!next.items||!next.items.length)return;var nextKey=String(next.date||'')+'|'+String(next.created_at||'')+'|'+String(next.editorial_updated_at||'');if(nextKey===batchKey)return;gallery=next;items=next.items||[];batchKey=nextKey;idx=-1;busy=false;current.removeAttribute('src');incoming.removeAttribute('src');clearTimeout(timer);show(0,true)}
function refreshGallery(){fetch('/api/h5/photos',{cache:'no-store'}).then(function(r){return r.json()}).then(applyGallery).catch(function(){})}
fit();show(0,true);addEventListener('resize',fit);setInterval(refreshGallery,30000);stage.onclick=function(e){show(idx+(e.clientX>innerWidth/2?1:-1),false)};var sx=0;stage.addEventListener('touchstart',function(e){sx=e.touches[0].clientX},{passive:true});stage.addEventListener('touchend',function(e){var dx=e.changedTouches[0].clientX-sx;if(Math.abs(dx)>50)show(idx+(dx<0?1:-1),false)},{passive:true});})();
"""

_LITE_HTML = r"""<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b1020">
<title>RemotePanel · H5 Lite</title>
<style>/*__CSS__*/</style>
</head>
<body>
<div id="fit"><div id="stage">
  <header id="topbar">
    <div class="brandline">REMOTE PANEL</div>
    <div id="clock">--:--</div>
  </header>
  <section id="hero"></section>
  <main id="viewport"></main>
  <footer id="footer">
    <div id="dots"></div>
    <div id="status">LIVE</div>
  </footer>
  <div id="progress"><div id="progressFill"></div></div>
</div></div>
<script>
window.__H5_STATE__ = "__PAYLOAD__";
window.__H5_ACTIVE__ = "__ACTIVE__";
window.__STAGE_W__ = /*__STAGE_W__*/0;
window.__STAGE_H__ = /*__STAGE_H__*/0;
</script>
<script>/*__JS__*/</script>
</body>
</html>
"""


_LITE_CSS = r"""
* { box-sizing:border-box; margin:0; padding:0; }
html, body { width:100%; height:100%; overflow:hidden; background:#07111f; color:#f8fafc; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC","Helvetica Neue",Arial,sans-serif; }
img { display:block; max-width:100%; }
#fit { position:fixed; inset:0; background:#07111f; overflow:hidden; }
#stage { position:absolute; left:50%; top:0; width:1080px; height:1800px; transform-origin:top center; overflow:hidden; }
#stage:before { content:""; position:absolute; inset:-12%; background:radial-gradient(42% 30% at 18% 12%, rgba(96,165,250,.24), transparent 62%), radial-gradient(38% 28% at 84% 18%, rgba(168,85,247,.20), transparent 60%), radial-gradient(44% 34% at 50% 100%, rgba(45,212,191,.16), transparent 62%); filter:blur(18px); opacity:.9; pointer-events:none; }
#stage:after { content:""; position:absolute; inset:0; background:linear-gradient(180deg, rgba(255,255,255,.05), transparent 20%, transparent 78%, rgba(0,0,0,.22)), radial-gradient(circle at top, rgba(255,255,255,.08), transparent 42%); pointer-events:none; }
#topbar { position:absolute; left:34px; right:34px; top:16px; height:60px; z-index:6; display:flex; align-items:flex-start; justify-content:space-between; }
.brandline { font-size:17px; letter-spacing:.32em; color:#e5eefc; font-weight:800; opacity:.94; padding-top:6px; }
#clock { font-size:50px; font-weight:900; letter-spacing:-.05em; line-height:.92; text-shadow:0 8px 24px rgba(0,0,0,.30); opacity:.90; }
#hero { position:absolute; left:34px; right:34px; top:84px; height:122px; border-radius:28px; padding:12px 22px 10px; border:1px solid rgba(255,255,255,.11); background:linear-gradient(135deg, rgba(255,255,255,.16), rgba(255,255,255,.05)); box-shadow:0 16px 42px rgba(0,0,0,.24), inset 0 1px 0 rgba(255,255,255,.10); backdrop-filter:blur(12px); z-index:5; overflow:hidden; }
#hero:before { content:""; position:absolute; inset:0; background:linear-gradient(90deg, rgba(255,255,255,.10), transparent 30%, transparent 72%, rgba(255,255,255,.05)); pointer-events:none; }
#hero .kicker { position:relative; font-size:15px; letter-spacing:.22em; text-transform:uppercase; opacity:.80; }
#hero .title { position:relative; margin-top:4px; font-size:48px; line-height:.94; font-weight:900; letter-spacing:-.05em; text-shadow:0 10px 28px rgba(0,0,0,.24); }
#hero .sub { position:relative; margin-top:4px; font-size:16px; line-height:1.16; opacity:.80; }
#viewport { position:absolute; left:34px; right:34px; top:220px; bottom:74px; z-index:4; }
.screen { position:absolute; inset:0; display:none; }
.screen.active { display:block; }
.card { position:relative; border-radius:28px; padding:22px 24px; border:1px solid rgba(255,255,255,.10); background:linear-gradient(180deg, rgba(255,255,255,.10), rgba(255,255,255,.04)); box-shadow:0 16px 36px rgba(0,0,0,.22), inset 0 1px 0 rgba(255,255,255,.06); overflow:hidden; backdrop-filter:blur(10px); }
.card:before { content:""; position:absolute; inset:0; background:linear-gradient(135deg, rgba(255,255,255,.05), transparent 34%, transparent 72%, rgba(255,255,255,.03)); pointer-events:none; }
.card.dark { background:linear-gradient(180deg, rgba(7,14,28,.80), rgba(6,11,24,.58)); }
.card.hero-card { padding:20px; }
.card.tight { padding:18px 20px; }
.card + .card { margin-top:18px; }
.label { font-size:18px; letter-spacing:.22em; text-transform:uppercase; opacity:.72; }
.big { font-size:78px; line-height:.92; font-weight:900; letter-spacing:-.05em; }
.huge { font-size:150px; line-height:.8; font-weight:900; letter-spacing:-.08em; }
.mid { font-size:34px; line-height:1.14; font-weight:760; }
.body { font-size:27px; line-height:1.28; }
.small { font-size:20px; line-height:1.34; opacity:.88; }
.tiny { font-size:16px; line-height:1.35; opacity:.72; }
.muted { opacity:.70; }
.row { margin-top:12px; }
.badge { display:inline-block; padding:10px 14px; border-radius:999px; font-size:18px; font-weight:800; margin:8px 8px 0 0; color:#ecf3ff; background:rgba(255,255,255,.10); border:1px solid rgba(255,255,255,.08); box-shadow:inset 0 1px 0 rgba(255,255,255,.08); }
.badge.gold { background:linear-gradient(135deg, rgba(251,191,36,.26), rgba(245,158,11,.10)); color:#fff7d6; }
.badge.cyan { background:linear-gradient(135deg, rgba(34,211,238,.24), rgba(56,189,248,.10)); }
.badge.pink { background:linear-gradient(135deg, rgba(244,114,182,.26), rgba(244,63,94,.10)); }
.badge.green { background:linear-gradient(135deg, rgba(52,211,153,.24), rgba(16,185,129,.10)); }
.meter { margin-top:16px; height:18px; border-radius:999px; background:rgba(255,255,255,.10); overflow:hidden; box-shadow:inset 0 2px 6px rgba(0,0,0,.18); }
.meter > span { display:block; height:100%; background:linear-gradient(90deg, #ffffff, rgba(255,255,255,.84)); box-shadow:0 0 20px rgba(255,255,255,.24); }
.statgrid3 { display:grid; grid-template-columns:repeat(3, 1fr); gap:14px; margin-top:16px; }
.statbox { padding:15px 16px 16px; border-radius:22px; background:linear-gradient(180deg, rgba(255,255,255,.08), rgba(255,255,255,.03)); border:1px solid rgba(255,255,255,.08); }
.statbox .sv { margin-top:8px; font-size:44px; font-weight:900; letter-spacing:-.04em; }
.two-col, .split-hero, .hero-band, .hero-split, .kpi-grid, .feature-grid, .poster-grid, .feed-grid, .weather-grid, .print-layout { display:grid; gap:18px; }
.two-col { grid-template-columns:1.12fr .88fr; }
.split-hero { grid-template-columns:1.08fr .92fr; align-items:stretch; }
.hero-band { grid-template-columns:1.3fr .7fr; align-items:stretch; }
.hero-split { grid-template-columns:1fr 1fr; align-items:stretch; }
.kpi-grid { grid-template-columns:repeat(4, 1fr); }
.feature-grid { grid-template-columns:repeat(2, 1fr); }
.poster-grid { grid-template-columns:repeat(3, 1fr); gap:16px; }
.feed-grid { grid-template-columns:1.05fr .95fr; }
.weather-grid { grid-template-columns:1fr .9fr; }
.print-layout { grid-template-columns:.92fr 1.08fr; }
.stack-12 > * + * { margin-top:12px; }
.stack-14 > * + * { margin-top:14px; }
.stack-16 > * + * { margin-top:16px; }
.thumb { width:100%; height:244px; object-fit:cover; border-radius:22px; background:rgba(255,255,255,.08); box-shadow:0 12px 26px rgba(0,0,0,.20); }
.thumb.tall { height:500px; }
.thumb.medium { height:320px; }
.thumb.poster { height:310px; object-fit:contain; background:linear-gradient(180deg, rgba(255,255,255,.06), rgba(255,255,255,.02)); }
.thumb.gamewide { height:185px; object-fit:cover; }
.thumb.cinema { height:260px; object-fit:cover; }
.cover-title { margin-top:12px; font-size:30px; line-height:1.08; font-weight:860; }
.cover-meta { margin-top:8px; font-size:20px; line-height:1.28; opacity:.86; }
.poster-card { padding:12px; border-radius:22px; background:linear-gradient(180deg, rgba(255,255,255,.08), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.10); box-shadow:0 16px 32px rgba(0,0,0,.22); }
.poster-caption { margin-top:10px; font-size:20px; line-height:1.2; font-weight:760; }
.poster-date { margin-top:6px; font-size:16px; opacity:.72; }
.quote { padding:22px 24px; border-radius:26px; background:linear-gradient(135deg, rgba(255,255,255,.11), rgba(255,255,255,.05)); font-size:30px; line-height:1.22; font-weight:720; box-shadow:0 16px 30px rgba(0,0,0,.20); }
.list-item { padding:14px 0; border-top:1px solid rgba(255,255,255,.10); }
.list-item:first-child { border-top:0; padding-top:0; }
.alert-row { margin-top:12px; padding:18px 18px 18px 20px; border-radius:22px; background:linear-gradient(135deg, rgba(255,255,255,.10), rgba(255,255,255,.04)); border-left:8px solid rgba(255,255,255,.74); box-shadow:0 12px 28px rgba(0,0,0,.18); }
.alert-row .sev { font-size:16px; letter-spacing:.18em; text-transform:uppercase; opacity:.74; }
.alert-row .ttl { margin-top:6px; font-size:30px; line-height:1.12; font-weight:860; }
.alert-row .txt { margin-top:8px; font-size:22px; line-height:1.28; opacity:.88; }
.chat-bubble { padding:18px 20px; border-radius:24px; background:linear-gradient(180deg, rgba(255,255,255,.10), rgba(255,255,255,.05)); border:1px solid rgba(255,255,255,.08); box-shadow:0 12px 24px rgba(0,0,0,.18); }
.chat-bubble.user { background:linear-gradient(180deg, rgba(255,255,255,.16), rgba(255,255,255,.07)); }
.chat-who { font-size:16px; letter-spacing:.18em; text-transform:uppercase; opacity:.70; }
.chat-text { margin-top:8px; font-size:27px; line-height:1.24; }
.marquee-number { font-size:132px; line-height:.84; font-weight:900; letter-spacing:-.08em; text-shadow:0 12px 30px rgba(0,0,0,.20); }
.kpi-chip { padding:14px 16px; border-radius:22px; background:linear-gradient(180deg, rgba(255,255,255,.10), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); }
.kpi-chip .k { font-size:15px; letter-spacing:.16em; text-transform:uppercase; opacity:.7; }
.kpi-chip .v { margin-top:6px; font-size:34px; font-weight:860; letter-spacing:-.04em; }
.feature-tile { position:relative; min-height:198px; padding:18px; border-radius:26px; overflow:hidden; background:linear-gradient(180deg, rgba(255,255,255,.09), rgba(255,255,255,.03)); border:1px solid rgba(255,255,255,.08); box-shadow:0 14px 28px rgba(0,0,0,.20); }
.feature-tile .eyebrow { font-size:15px; letter-spacing:.16em; text-transform:uppercase; opacity:.72; }
.feature-tile .headline { margin-top:8px; font-size:30px; line-height:1.08; font-weight:860; }
.feature-tile .meta { margin-top:10px; font-size:18px; line-height:1.3; opacity:.82; }
.feature-tile .stat { position:absolute; right:16px; bottom:16px; font-size:40px; font-weight:900; letter-spacing:-.05em; opacity:.94; }
.launch-shell { position:relative; overflow:hidden; border-radius:34px; height:860px; min-height:0; background:linear-gradient(135deg, rgba(34,211,238,.22) 0%, rgba(59,130,246,.16) 28%, rgba(168,85,247,.18) 58%, rgba(244,114,182,.16) 100%); border:1px solid rgba(125,211,252,.18); box-shadow:inset 0 1px 0 rgba(255,255,255,.10), 0 26px 60px rgba(0,0,0,.32); }
.launch-shell:before { content:""; position:absolute; inset:-18% -10%; background:radial-gradient(circle at 18% 22%, rgba(255,255,255,.20), transparent 22%), radial-gradient(circle at 82% 18%, rgba(125,211,252,.18), transparent 26%), radial-gradient(circle at 74% 78%, rgba(244,114,182,.20), transparent 22%), radial-gradient(circle at 24% 76%, rgba(45,212,191,.20), transparent 22%); filter:blur(2px); animation:launchNebula 16s ease-in-out infinite alternate; }
.launch-shell:after { content:""; position:absolute; inset:0; background:linear-gradient(180deg, rgba(255,255,255,.08), transparent 24%, transparent 72%, rgba(255,255,255,.04)); pointer-events:none; }
.launch-grid { position:relative; display:grid; grid-template-columns:1.2fr .8fr; gap:22px; align-items:stretch; height:100%; min-height:0; padding:34px; }
.launch-copy { position:relative; z-index:2; display:flex; flex-direction:column; justify-content:space-between; }
.launch-kicker { display:inline-flex; align-items:center; gap:12px; padding:10px 16px; border-radius:999px; background:rgba(15,23,42,.34); border:1px solid rgba(255,255,255,.12); font-size:18px; letter-spacing:.22em; text-transform:uppercase; color:#dbeafe; backdrop-filter:blur(12px); }
.launch-kicker:before { content:""; width:12px; height:12px; border-radius:999px; background:linear-gradient(180deg, #67e8f9, #38bdf8); box-shadow:0 0 18px rgba(103,232,249,.7); animation:pulseGlowDot 2.8s ease-in-out infinite; }
.launch-title { margin-top:20px; font-size:118px; line-height:.86; font-weight:950; letter-spacing:-.07em; color:#fff; text-shadow:0 14px 30px rgba(15,23,42,.28); }
.launch-title .accent { display:block; background:linear-gradient(90deg, #67e8f9 0%, #a5b4fc 38%, #f9a8d4 72%, #fde68a 100%); -webkit-background-clip:text; background-clip:text; color:transparent; }
.launch-subcopy { margin-top:20px; max-width:92%; font-size:28px; line-height:1.34; color:rgba(241,245,249,.90); }
.launch-badges { display:flex; flex-wrap:wrap; gap:12px; margin-top:22px; }
.launch-badge { padding:10px 14px; border-radius:999px; background:rgba(255,255,255,.10); border:1px solid rgba(255,255,255,.14); font-size:17px; letter-spacing:.12em; text-transform:uppercase; color:#fff; backdrop-filter:blur(10px); }
.launch-stats { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:14px; margin-top:28px; }
.launch-stat { padding:18px 18px 16px; border-radius:24px; background:rgba(15,23,42,.30); border:1px solid rgba(255,255,255,.12); backdrop-filter:blur(16px); box-shadow:inset 0 1px 0 rgba(255,255,255,.08); }
.launch-stat .k { font-size:16px; letter-spacing:.18em; text-transform:uppercase; color:rgba(191,219,254,.86); }
.launch-stat .v { margin-top:10px; font-size:34px; line-height:1.02; font-weight:900; color:#fff; display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; overflow:hidden; overflow-wrap:anywhere; max-height:2.08em; }
.launch-stat .d { margin-top:8px; font-size:18px; line-height:1.28; color:rgba(226,232,240,.78); }
.launch-visual { position:relative; z-index:2; min-height:620px; }
.launch-orbit { position:absolute; inset:16px 0 0 0; display:flex; align-items:center; justify-content:center; }
.launch-ring { position:absolute; border-radius:999px; border:1px solid rgba(255,255,255,.16); }
.launch-ring.r1 { width:460px; height:460px; animation:orbitSpin 18s linear infinite; }
.launch-ring.r2 { width:330px; height:330px; border-style:dashed; border-color:rgba(125,211,252,.24); animation:orbitSpinReverse 12s linear infinite; }
.launch-ring.r3 { width:210px; height:210px; border-color:rgba(244,114,182,.28); animation:orbitPulse 5.2s ease-in-out infinite; }
.launch-core { position:relative; width:250px; height:250px; border-radius:40px; background:linear-gradient(135deg, rgba(15,23,42,.94), rgba(30,41,59,.72)); border:1px solid rgba(255,255,255,.14); box-shadow:0 0 0 10px rgba(255,255,255,.03), 0 30px 70px rgba(15,23,42,.36); display:flex; flex-direction:column; justify-content:center; align-items:center; text-align:center; overflow:hidden; }
.launch-core:before { content:""; position:absolute; inset:-20% -10%; background:conic-gradient(from 0deg, rgba(103,232,249,.0), rgba(103,232,249,.34), rgba(168,85,247,.22), rgba(251,191,36,.18), rgba(103,232,249,.0)); animation:orbitSpin 10s linear infinite; }
.launch-core:after { content:""; position:absolute; inset:1px; border-radius:38px; background:linear-gradient(180deg, rgba(15,23,42,.94), rgba(30,41,59,.76)); }
.launch-core-label, .launch-core-value, .launch-core-meta { position:relative; z-index:1; }
.launch-core-label { font-size:18px; letter-spacing:.22em; text-transform:uppercase; color:rgba(191,219,254,.86); }
.launch-core-value { margin-top:10px; font-size:96px; line-height:.86; font-weight:950; color:#fff; }
.launch-core-meta { margin-top:12px; font-size:20px; line-height:1.24; color:rgba(226,232,240,.80); max-width:80%; }
.launch-float { position:absolute; padding:16px 18px; border-radius:24px; background:rgba(15,23,42,.38); border:1px solid rgba(255,255,255,.12); backdrop-filter:blur(16px); box-shadow:0 18px 38px rgba(15,23,42,.22); }
.launch-float .t { font-size:16px; letter-spacing:.18em; text-transform:uppercase; color:rgba(191,219,254,.82); }
.launch-float .v { margin-top:8px; font-size:34px; line-height:.96; font-weight:900; color:#fff; }
.launch-float .m { margin-top:6px; font-size:18px; line-height:1.22; color:rgba(226,232,240,.76); }
.launch-float.f1 { left:0; top:40px; width:220px; animation:launchFloatA 7.2s ease-in-out infinite; }
.launch-float.f2 { right:8px; top:102px; width:210px; animation:launchFloatB 8s ease-in-out infinite; }
.launch-float.f3 { left:26px; bottom:86px; width:230px; animation:launchFloatC 6.8s ease-in-out infinite; }
.launch-float.f4 { right:34px; bottom:38px; width:230px; animation:launchFloatD 7.8s ease-in-out infinite; }
@keyframes launchNebula { 0% { transform:translate3d(0,0,0) scale(1); opacity:.92; } 100% { transform:translate3d(12px,-18px,0) scale(1.08); opacity:1; } }
@keyframes pulseGlowDot { 0%,100% { transform:scale(1); box-shadow:0 0 18px rgba(103,232,249,.7); } 50% { transform:scale(.82); box-shadow:0 0 28px rgba(103,232,249,.95); } }
@keyframes orbitSpin { from { transform:rotate(0deg); } to { transform:rotate(360deg); } }
@keyframes orbitSpinReverse { from { transform:rotate(360deg); } to { transform:rotate(0deg); } }
@keyframes orbitPulse { 0%,100% { transform:scale(1); opacity:.92; } 50% { transform:scale(1.08); opacity:1; } }
@keyframes launchFloatA { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(10px,-18px,0); } }
@keyframes launchFloatB { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(-12px,14px,0); } }
@keyframes launchFloatC { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(8px,-14px,0); } }
@keyframes launchFloatD { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(-10px,-16px,0); } }
.hero-art { position:relative; overflow:hidden; min-height:328px; border-radius:28px; }
.hero-art .thumb { height:100%; min-height:328px; border-radius:28px; }
.news-art { min-height:240px; background:linear-gradient(135deg, rgba(56,189,248,.26), rgba(129,140,248,.18) 48%, rgba(244,114,182,.16)); box-shadow:inset 0 0 0 1px rgba(255,255,255,.08); }
.news-art:before { content:""; position:absolute; inset:0; background:radial-gradient(circle at 20% 28%, rgba(255,255,255,.16), transparent 20%), radial-gradient(circle at 78% 26%, rgba(255,255,255,.14), transparent 18%), linear-gradient(180deg, rgba(255,255,255,.08), transparent 32%); }
.github-art { min-height:240px; background:linear-gradient(135deg, rgba(17,24,39,.92), rgba(30,41,59,.78) 52%, rgba(56,189,248,.16)); box-shadow:inset 0 0 0 1px rgba(255,255,255,.06); }
.github-art:before { content:"</>"; position:absolute; right:24px; top:18px; font-size:78px; font-weight:900; letter-spacing:-.08em; color:rgba(255,255,255,.18); }
.github-art:after { content:"git push · merge · ship"; position:absolute; left:22px; bottom:78px; font-size:20px; letter-spacing:.18em; text-transform:uppercase; color:rgba(255,255,255,.34); }
.hero-overlay { position:absolute; left:0; right:0; bottom:0; padding:20px 22px; background:linear-gradient(180deg, transparent 0%, rgba(0,0,0,.12) 18%, rgba(0,0,0,.72) 100%); }
.hero-overlay .headline { font-size:42px; line-height:1.02; font-weight:900; }
.hero-overlay .meta { margin-top:8px; font-size:20px; line-height:1.28; opacity:.88; }
.hero-side { display:flex; flex-direction:column; gap:16px; }
.glow-line { height:1px; background:linear-gradient(90deg, rgba(255,255,255,.0), rgba(255,255,255,.38), rgba(255,255,255,.0)); opacity:.72; }
.weather-strip { display:grid; grid-template-columns:repeat(5, 1fr); gap:12px; margin-top:16px; }
.weather-pill { padding:14px 10px; border-radius:20px; text-align:center; background:linear-gradient(180deg, rgba(255,255,255,.10), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); }
.weather-pill .d { font-size:16px; letter-spacing:.12em; opacity:.72; }
.weather-pill .t { margin-top:8px; font-size:34px; font-weight:900; }
.weather-pill .m { margin-top:6px; font-size:16px; opacity:.78; }
.weather-week-grid { display:grid; grid-template-columns:repeat(3, 1fr); gap:18px; margin-top:20px; }
.weather-day-card { padding:18px 18px 16px; border-radius:26px; background:linear-gradient(180deg, rgba(255,255,255,.11), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); box-shadow:0 16px 30px rgba(0,0,0,.20); min-height:208px; }
.weather-day-card .top { display:flex; align-items:flex-start; justify-content:space-between; gap:10px; }
.weather-day-card .day { font-size:20px; letter-spacing:.16em; text-transform:uppercase; opacity:.78; font-weight:800; }
.weather-day-card .icon { font-size:36px; line-height:1; opacity:.98; }
.weather-day-card .high { margin-top:14px; font-size:54px; line-height:.9; font-weight:900; letter-spacing:-.06em; }
.weather-day-card .low { margin-top:8px; font-size:21px; opacity:.84; }
.weather-day-card .desc { margin-top:12px; font-size:20px; line-height:1.26; min-height:50px; opacity:.90; }
.weather-day-card .bar { margin-top:14px; height:12px; border-radius:999px; background:rgba(255,255,255,.14); overflow:hidden; }
.weather-day-card .bar span { display:block; height:100%; background:linear-gradient(90deg, rgba(255,255,255,.96), rgba(255,255,255,.72)); }
.weather-summary-grid { display:grid; grid-template-columns:1.14fr .86fr; gap:18px; margin-top:18px; }
.weather-summary-card { padding:24px 24px; border-radius:28px; background:linear-gradient(180deg, rgba(255,255,255,.11), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); box-shadow:0 18px 34px rgba(0,0,0,.20); }
.weather-summary-card .title { font-size:19px; letter-spacing:.18em; text-transform:uppercase; opacity:.74; }
.weather-summary-card .headline { margin-top:12px; font-size:40px; line-height:1.04; font-weight:900; }
.weather-summary-card .copy { margin-top:14px; font-size:24px; line-height:1.32; opacity:.9; }
.weather-summary-card .mini { margin-top:16px; font-size:18px; line-height:1.32; opacity:.74; }
.weather-scene { position:relative; min-height:320px; overflow:hidden; border-radius:28px; background:linear-gradient(180deg, rgba(125,211,252,.20) 0%, rgba(59,130,246,.14) 48%, rgba(14,116,144,.10) 100%); }
.weather-scene:before { content:""; position:absolute; inset:-20% -10% auto -10%; height:78%; background:radial-gradient(circle at 70% 24%, rgba(253,224,71,.32), transparent 20%), radial-gradient(circle at 24% 18%, rgba(255,255,255,.15), transparent 26%), radial-gradient(circle at 50% 50%, rgba(14,165,233,.16), transparent 60%); animation:skyShift 18s ease-in-out infinite alternate; }
.weather-sun { position:absolute; right:64px; top:42px; width:128px; height:128px; border-radius:50%; background:radial-gradient(circle at 35% 35%, #fff8cc 0%, #fde68a 34%, #fbbf24 68%, rgba(251,191,36,.92) 100%); box-shadow:0 0 36px rgba(251,191,36,.46), 0 0 88px rgba(253,224,71,.28); animation:sunPulse 4.8s ease-in-out infinite; }
.weather-sun:before { content:""; position:absolute; inset:-18px; border-radius:50%; border:2px solid rgba(255,244,190,.26); animation:sunHalo 6s linear infinite; }
.weather-cloud { position:absolute; border-radius:999px; background:linear-gradient(180deg, rgba(255,255,255,.88), rgba(255,255,255,.54)); box-shadow:0 10px 24px rgba(15,23,42,.12); opacity:.90; }
.weather-cloud:before, .weather-cloud:after { content:""; position:absolute; border-radius:999px; background:inherit; }
.weather-cloud:before { width:58%; height:92%; left:12%; top:-34%; }
.weather-cloud:after { width:42%; height:82%; right:12%; top:-24%; }
.weather-cloud.c1 { left:56px; top:62px; width:148px; height:42px; animation:cloudDriftA 17s ease-in-out infinite; }
.weather-cloud.c2 { left:198px; top:118px; width:118px; height:36px; opacity:.76; animation:cloudDriftB 21s ease-in-out infinite; }
.weather-cloud.c3 { right:178px; top:142px; width:138px; height:40px; opacity:.66; animation:cloudDriftC 19s ease-in-out infinite; }
.weather-foreground { position:absolute; inset:auto 0 0 0; height:42%; background:linear-gradient(180deg, rgba(255,255,255,0) 0%, rgba(5,150,105,.08) 30%, rgba(8,47,73,.24) 100%); }
.weather-cityline { position:absolute; left:0; right:0; bottom:0; height:118px; background:linear-gradient(180deg, rgba(15,23,42,0) 0%, rgba(15,23,42,.10) 16%, rgba(15,23,42,.48) 100%); }
.weather-cityline:before { content:""; position:absolute; left:24px; right:24px; bottom:0; height:90px; background:linear-gradient(90deg, rgba(255,255,255,.16) 0 3%, transparent 3% 6%, rgba(255,255,255,.08) 6% 10%, transparent 10% 14%, rgba(255,255,255,.14) 14% 19%, transparent 19% 23%, rgba(255,255,255,.10) 23% 26%, transparent 26% 32%, rgba(255,255,255,.14) 32% 36%, transparent 36% 42%, rgba(255,255,255,.09) 42% 48%, transparent 48% 55%, rgba(255,255,255,.15) 55% 60%, transparent 60% 66%, rgba(255,255,255,.08) 66% 72%, transparent 72% 79%, rgba(255,255,255,.12) 79% 85%, transparent 85% 91%, rgba(255,255,255,.10) 91% 100%); clip-path:polygon(0 100%, 0 52%, 4% 52%, 4% 18%, 9% 18%, 9% 64%, 15% 64%, 15% 30%, 22% 30%, 22% 78%, 29% 78%, 29% 12%, 36% 12%, 36% 58%, 43% 58%, 43% 26%, 50% 26%, 50% 72%, 58% 72%, 58% 34%, 66% 34%, 66% 82%, 73% 82%, 73% 22%, 81% 22%, 81% 66%, 89% 66%, 89% 40%, 96% 40%, 96% 100%, 100% 100%); opacity:.32; }
@keyframes sunPulse { 0%,100% { transform:scale(1); box-shadow:0 0 36px rgba(251,191,36,.46), 0 0 88px rgba(253,224,71,.28); } 50% { transform:scale(1.06); box-shadow:0 0 44px rgba(251,191,36,.58), 0 0 104px rgba(253,224,71,.34); } }
@keyframes sunHalo { from { transform:scale(.94) rotate(0deg); opacity:.42; } 50% { opacity:.16; } to { transform:scale(1.08) rotate(360deg); opacity:.42; } }
@keyframes cloudDriftA { 0%,100% { transform:translateX(0px) translateY(0px); } 50% { transform:translateX(22px) translateY(-6px); } }
@keyframes cloudDriftB { 0%,100% { transform:translateX(0px) translateY(0px); } 50% { transform:translateX(-18px) translateY(5px); } }
@keyframes cloudDriftC { 0%,100% { transform:translateX(0px) translateY(0px); } 50% { transform:translateX(16px) translateY(-5px); } }
@keyframes skyShift { 0% { transform:translate3d(0,0,0) scale(1); opacity:.92; } 100% { transform:translate3d(0,-10px,0) scale(1.04); opacity:1; } }
.inv-grid { display:grid; grid-template-columns:repeat(2, 1fr); gap:16px; }
.inv-card { padding:16px 18px; border-radius:24px; background:linear-gradient(180deg, rgba(255,255,255,.09), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); min-height:176px; box-shadow:0 14px 26px rgba(0,0,0,.18); }
.inv-top { font-size:16px; letter-spacing:.16em; text-transform:uppercase; opacity:.70; }
.inv-name { margin-top:8px; font-size:25px; line-height:1.12; font-weight:840; }
.inv-meta { margin-top:8px; font-size:18px; line-height:1.25; opacity:.84; }
.color-row { margin-top:10px; }
.color-dot { display:inline-block; width:18px; height:18px; border-radius:999px; margin-right:8px; border:2px solid rgba(255,255,255,.40); vertical-align:middle; box-shadow:0 0 10px rgba(255,255,255,.16); }
.inv-pct { margin-top:10px; font-size:30px; font-weight:900; letter-spacing:-.03em; }
.low-stock { box-shadow:0 0 0 1px rgba(251,113,133,.32) inset, 0 14px 26px rgba(0,0,0,.18); }
.mini-columns { display:grid; grid-template-columns:repeat(2, 1fr); gap:14px; }
.mini-card { padding:16px 18px; border-radius:22px; background:linear-gradient(180deg, rgba(255,255,255,.09), rgba(255,255,255,.04)); border:1px solid rgba(255,255,255,.08); }
.glass-art { background:linear-gradient(135deg, rgba(56,189,248,.24), rgba(129,140,248,.16) 56%, rgba(45,212,191,.14)); box-shadow:inset 0 0 0 1px rgba(255,255,255,.08), 0 14px 28px rgba(0,0,0,.18); }
.mini-card .title { font-size:18px; letter-spacing:.12em; text-transform:uppercase; opacity:.72; }
.mini-card .value { margin-top:10px; font-size:44px; line-height:.92; font-weight:900; letter-spacing:-.05em; }
.mini-card .desc { margin-top:8px; font-size:18px; line-height:1.28; opacity:.82; }
#footer { position:absolute; left:34px; right:34px; bottom:36px; height:32px; z-index:6; display:flex; align-items:center; justify-content:space-between; }
#dots { display:flex; align-items:center; gap:10px; }
.dot { width:12px; height:12px; border-radius:50%; background:rgba(255,255,255,.24); box-shadow:inset 0 1px 0 rgba(255,255,255,.10); }
.dot.active { width:42px; border-radius:999px; background:linear-gradient(90deg, #ffffff, rgba(255,255,255,.82)); box-shadow:0 0 16px rgba(255,255,255,.22); }
#status { font-size:18px; letter-spacing:.16em; opacity:.86; }
#progress { position:absolute; left:0; right:0; bottom:0; height:8px; background:rgba(255,255,255,.08); z-index:7; }
#progressFill { height:100%; width:0; background:linear-gradient(90deg, rgba(255,255,255,.88), #ffffff); box-shadow:0 0 16px rgba(255,255,255,.18); }
.motion-slide-up { animation:motionSlideUp 1.1s cubic-bezier(.22,.61,.36,1) both; }
.motion-slide-down { animation:motionSlideDown 1.1s cubic-bezier(.22,.61,.36,1) both; }
.motion-title-float { animation:titleFloat 6s ease-in-out infinite; }
.motion-card-float { animation:cardFloat 8s ease-in-out infinite; }
.motion-card-float-slow { animation:cardFloatSlow 12s ease-in-out infinite; }
.motion-card-float-fast { animation:cardFloatFast 5.4s ease-in-out infinite; }
.motion-image-drift { animation:imageDrift 10s ease-in-out infinite alternate; will-change:transform; }
.motion-image-drift-slow { animation:imageDriftSlow 16s ease-in-out infinite alternate; will-change:transform; }
.motion-ticker { animation:textTicker 14s linear infinite alternate; display:inline-block; white-space:nowrap; }
.motion-pulse-glow { animation:pulseGlow 4.4s ease-in-out infinite; }
.motion-orbit { animation:orbitDrift 18s ease-in-out infinite alternate; }
.flyin-left { animation:flyInLeft 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-right { animation:flyInRight 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-up { animation:flyInUp 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-down { animation:flyInDown 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-zoom { animation:flyInZoom 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-rotate-left { animation:flyInRotateLeft 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-rotate-right { animation:flyInRotateRight 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-diag-left { animation:flyInDiagLeft 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-diag-right { animation:flyInDiagRight 1.5s cubic-bezier(.16,.84,.24,1) both; }
.flyin-curtain { animation:flyInCurtain 1.5s cubic-bezier(.16,.84,.24,1) both; transform-origin:top center; }
.flyin-stagger-1 { animation-delay:0s; }
.flyin-stagger-2 { animation-delay:1.5s; }
.flyin-stagger-3 { animation-delay:3s; }
.flyin-stagger-4 { animation-delay:4.5s; }
.flyin-stagger-5 { animation-delay:6s; }
.flyin-stagger-6 { animation-delay:7.5s; }
@keyframes motionSlideUp { from { opacity:0; transform:translate3d(0,28px,0); } to { opacity:1; transform:translate3d(0,0,0); } }
@keyframes motionSlideDown { from { opacity:0; transform:translate3d(0,-22px,0); } to { opacity:1; transform:translate3d(0,0,0); } }
@keyframes titleFloat { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(0,-6px,0); } }
@keyframes cardFloat { 0%,100% { transform:translate3d(0,0,0) rotate(0deg); } 50% { transform:translate3d(0,-8px,0) rotate(.25deg); } }
@keyframes cardFloatSlow { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(0,-12px,0); } }
@keyframes cardFloatFast { 0%,100% { transform:translate3d(0,0,0); } 50% { transform:translate3d(0,-5px,0); } }
@keyframes imageDrift { 0% { transform:scale(1.02) translate3d(0,0,0); } 100% { transform:scale(1.08) translate3d(-12px,-8px,0); } }
@keyframes imageDriftSlow { 0% { transform:scale(1.01) translate3d(0,0,0); } 100% { transform:scale(1.06) translate3d(10px,-10px,0); } }
@keyframes textTicker { 0% { transform:translate3d(0,0,0); } 100% { transform:translate3d(-18px,0,0); } }
@keyframes pulseGlow { 0%,100% { filter:drop-shadow(0 0 0 rgba(255,255,255,0)); opacity:1; } 50% { filter:drop-shadow(0 0 12px rgba(255,255,255,.24)); opacity:.96; } }
@keyframes orbitDrift { 0% { transform:translate3d(0,0,0) rotate(0deg); } 100% { transform:translate3d(14px,-10px,0) rotate(4deg); } }
@keyframes flyInLeft { from { opacity:0; transform:translate3d(-140px,0,0) scale(.94) rotate(-3deg); } to { opacity:1; transform:translate3d(0,0,0) scale(1) rotate(0deg); } }
@keyframes flyInRight { from { opacity:0; transform:translate3d(140px,0,0) scale(.94) rotate(3deg); } to { opacity:1; transform:translate3d(0,0,0) scale(1) rotate(0deg); } }
@keyframes flyInUp { from { opacity:0; transform:translate3d(0,120px,0) scale(.96); } to { opacity:1; transform:translate3d(0,0,0) scale(1); } }
@keyframes flyInDown { from { opacity:0; transform:translate3d(0,-110px,0) scale(.96); } to { opacity:1; transform:translate3d(0,0,0) scale(1); } }
@keyframes flyInZoom { from { opacity:0; transform:scale(.72); filter:blur(10px); } to { opacity:1; transform:scale(1); filter:blur(0); } }
@keyframes flyInRotateLeft { from { opacity:0; transform:translate3d(-110px,34px,0) rotate(-10deg) scale(.88); } to { opacity:1; transform:translate3d(0,0,0) rotate(0deg) scale(1); } }
@keyframes flyInRotateRight { from { opacity:0; transform:translate3d(110px,-34px,0) rotate(10deg) scale(.88); } to { opacity:1; transform:translate3d(0,0,0) rotate(0deg) scale(1); } }
@keyframes flyInDiagLeft { from { opacity:0; transform:translate3d(-120px,120px,0) scale(.9); } to { opacity:1; transform:translate3d(0,0,0) scale(1); } }
@keyframes flyInDiagRight { from { opacity:0; transform:translate3d(120px,-120px,0) scale(.9); } to { opacity:1; transform:translate3d(0,0,0) scale(1); } }
@keyframes flyInCurtain { from { opacity:0; transform:translate3d(0,-90px,0) scaleY(.6); } to { opacity:1; transform:translate3d(0,0,0) scaleY(1); } }
.theme-work { background:linear-gradient(180deg,#091424 0%, #10284b 46%, #08101e 100%); }
.theme-work #hero, .theme-work .card { border-color:rgba(56,189,248,.26); }
.theme-work #hero { background:linear-gradient(135deg, rgba(14,116,144,.48), rgba(12,74,110,.28)); }
.theme-system { background:linear-gradient(180deg,#061914 0%, #0b3b31 46%, #06110f 100%); }
.theme-system #hero, .theme-system .card { border-color:rgba(52,211,153,.24); }
.theme-system #hero { background:linear-gradient(135deg, rgba(5,150,105,.42), rgba(6,95,70,.24)); }
.theme-weather { background:linear-gradient(180deg,#071b29 0%, #10405a 48%, #08131f 100%); }
.theme-weather #hero, .theme-weather .card { border-color:rgba(103,232,249,.24); }
.theme-weather #hero { background:linear-gradient(135deg, rgba(14,165,233,.34), rgba(21,94,117,.24)); }
.theme-news { background:linear-gradient(180deg,#16174a 0%, #40207f 48%, #120f27 100%); }
.theme-news #hero, .theme-news .card { border-color:rgba(168,85,247,.26); }
.theme-news #hero { background:linear-gradient(135deg, rgba(124,58,237,.36), rgba(76,29,149,.24)); }
.theme-media { background:linear-gradient(180deg,#271203 0%, #6b2c0c 48%, #180e0b 100%); }
.theme-media #hero, .theme-media .card { border-color:rgba(251,191,36,.28); }
.theme-media #hero { background:linear-gradient(135deg, rgba(217,119,6,.36), rgba(180,83,9,.22)); }
.theme-print { background:linear-gradient(180deg,#0a1930 0%, #1d4ed8 52%, #10152a 100%); }
.theme-print #hero, .theme-print .card { border-color:rgba(96,165,250,.24); }
.theme-print #hero { background:linear-gradient(135deg, rgba(37,99,235,.34), rgba(30,64,175,.22)); }
.theme-alerts { background:linear-gradient(180deg,#2f0a1d 0%, #5f1233 48%, #13060b 100%); }
.theme-alerts #hero, .theme-alerts .card { border-color:rgba(244,114,182,.26); }
.theme-alerts #hero { background:linear-gradient(135deg, rgba(225,29,72,.34), rgba(157,23,77,.22)); }
"""

_LITE_JS = r"""
'use strict';
(function () {
  var state = window.__H5_STATE__ || {};
  var STAGE_W = window.__STAGE_W__ || 1080;
  var STAGE_H = Math.min(window.__STAGE_H__ || 1800, 1800);
  function el(id){ return document.getElementById(id); }
  function num(v,d){ var n=Number(v); return isFinite(n)?n:(d||0); }
  function esc(v){ return String(v == null ? '' : v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  function fit(){
    var scale = Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H);
    var stage = el('stage');
    stage.style.width = STAGE_W + 'px';
    stage.style.height = STAGE_H + 'px';
    stage.style.transform = 'translateX(-50%) scale(' + scale + ')';
  }
  function pad2(v){ v = String(v); return v.length < 2 ? '0' + v : v; }
  function tickClock(){ var d=new Date(); el('clock').textContent = pad2(d.getHours()) + ':' + pad2(d.getMinutes()); }
  function familyToTheme(f){ if(f==='ops') return 'theme-system'; if(f==='weather') return 'theme-weather'; if(f==='news') return 'theme-news'; if(f==='entertainment') return 'theme-media'; if(f==='making') return 'theme-print'; return 'theme-work'; }
  function heroSubcopy(id){
    var map = {
      'work-cockpit':'任务优先 · 状态并行 · 提醒收束',
      'penguin-balance':'余额英雄数 + 趋势条 + 模型消费拆解',
      'schedule-board':'今日时间流 + 七天安排带 + 未来密度',
      'weather-today':'城市主天气 + 六日卡片 + 周趋势摘要',
      'system':'主机状态上屏 · VPS 余量下屏',
      'news':'头条封面 + 编辑导读 + 开源雷达',
      'gamer520':'Gamer520 首屏同步 + 游戏封面墙 + 标题列表',
      'steam':'主视觉游戏 + 推荐矩阵 + 补充清单',
      'movies':'热映情绪墙 + 海报阵列 + 院线氛围',
      'print-ops':'打印任务面板 + 设备热状态 + AMS 指挥墙'
    };
    return map[id] || '1080×1800 满屏版 · 大字 + 配图 + 自动轮播';
  }
  function byIdMap(){ var m={}, arr=state.screens||[]; for(var i=0;i<arr.length;i++) m[arr[i].id]=arr[i]; return m; }
  function meter(p){ return '<div class="meter"><span style="width:' + Math.max(0, Math.min(100, num(p,0))) + '%"></span></div>'; }
  function lines(arr, max, cls){ arr = arr || []; var out=''; for(var i=0;i<Math.min(arr.length, max||4);i++) out += '<div class="list-item ' + (cls||'body') + '">' + esc(arr[i]) + '</div>'; return out || '<div class="body">暂无内容</div>'; }
  function thumb(url, extra){ return url ? '<img class="thumb ' + (extra||'') + '" src="' + esc(url) + '" alt="">' : '<div class="thumb ' + (extra||'') + '"></div>'; }
  var metaMap = byIdMap();
  var order = (state.screens||[]).map(function(s){ return s.id; });
  if(!order.length) order = ['work-cockpit'];
  var fixed = String(new URLSearchParams(window.location.search).get('screen') || '').trim();
  var idx = fixed ? order.indexOf(fixed) : order.indexOf(window.__H5_ACTIVE__);
  if(idx < 0) idx = 0;
  var dwell = Math.max(6000, Math.min(300000, num((state.template||{}).dwell_seconds, 60) * 1000));
  var progTimer = null, progStart = 0;
  var renderCache = {};
  var preloadedImages = {};
  function stableSignature(src){
    try {
      var clone = JSON.parse(JSON.stringify(src || {}));
      if(clone.updated_at) delete clone.updated_at;
      if(clone.device){
        delete clone.device.last_switch_at;
        delete clone.device.last_content_refresh_at;
        delete clone.device.last_sent_at;
      }
      if(clone.template){
        delete clone.template.rotate_index;
        delete clone.template.rotate_total;
        delete clone.template.page_index;
        delete clone.template.page_name;
      }
      return JSON.stringify(clone);
    } catch (e) {
      return '';
    }
  }
  var lastRefreshSig = stableSignature(state);

  function hero(meta){
    el('stage').className = familyToTheme(meta.family || 'work');
    el('hero').innerHTML = '<div class="kicker motion-slide-down">' + esc(meta.subtitle || '') + '</div><div class="title motion-title-float">' + esc(meta.title || meta.id) + '</div><div class="sub motion-slide-up">' + esc(heroSubcopy(meta.id || '')) + '</div>';
  }
  function dots(){ var html=''; for(var i=0;i<order.length;i++) html += '<span class="dot ' + (i===idx?'active':'') + '"></span>'; el('dots').innerHTML = html; }
  function screenSignature(id){
    try {
      return stableSignature({ id:id, meta:metaMap[id] || {}, payload:renderScreen(id) });
    } catch (e) {
      return id + '::fallback';
    }
  }
  function collectImageUrls(src){
    var urls = [];
    function push(url){
      url = String(url || '').trim();
      if(!url) return;
      if(urls.indexOf(url) < 0) urls.push(url);
    }
    var data = src || state || {};
    push('/assets/ipad/weather-hero.png');
    var steamItems = ((data.steam || {}).new_releases || []).concat(((data.steam || {}).top_sellers || []));
    for(var si=0; si<steamItems.length; si++) push(steamItems[si].header_url || steamItems[si].capsule_url || steamItems[si].screenshot_url || '');
    var movieItems = data.movies || [];
    for(var mi=0; mi<movieItems.length; mi++) push(movieItems[mi].poster_url || '');
    var gamerItems = ((data.gamer520 || {}).items || []);
    for(var gi=0; gi<gamerItems.length; gi++) push(gamerItems[gi].image_url || '');
    var newsItems = ((data.news || {}).daily_items || []);
    for(var ni=0; ni<newsItems.length; ni++) push(newsItems[ni].image_url || '');
    return urls;
  }
  function preloadImages(src){
    var urls = collectImageUrls(src);
    for(var i=0; i<urls.length; i++){
      var url = urls[i];
      if(preloadedImages[url]) continue;
      var img = new Image();
      img.decoding = 'async';
      img.loading = 'eager';
      img.src = url;
      preloadedImages[url] = true;
    }
  }
  function buildRenderCache(){
    renderCache = {};
    for(var i=0;i<order.length;i++){
      var id = order[i];
      renderCache[id] = { html: renderScreen(id), sig: screenSignature(id) };
    }
  }

  function renderScreen(id){
    var w = state.weather || {}, wk = state.work || {}, sess = state.session || {}, ops = state.ops || {}, vps = state.vps || {}, news = state.news || {}, steam = state.steam || {}, movies = state.movies || [], pr = (state.print||{}).primary || {}, alerts = state.alerts || [], daily = state.daily || {};
    var gamer520 = state.gamer520 || {};
    var weatherWeekly = w.weekly || [];
    function badgeRow(arr, cls){ var out=''; arr=arr||[]; for(var i=0;i<arr.length;i++) out += '<span class="badge ' + (cls||'') + '">' + esc(arr[i]) + '</span>'; return out; }
    function statChip(k,v){ return '<div class="kpi-chip"><div class="k">' + esc(k) + '</div><div class="v">' + esc(v) + '</div></div>'; }
    function featureTile(eyebrow, headline, meta, stat){ return '<div class="feature-tile"><div class="eyebrow">' + esc(eyebrow) + '</div><div class="headline">' + esc(headline) + '</div><div class="meta">' + esc(meta) + '</div>' + (stat ? '<div class="stat">' + esc(stat) + '</div>' : '') + '</div>'; }
    function topList(arr, max){ var out=''; arr=arr||[]; for(var i=0;i<Math.min(arr.length, max||4);i++) out += '<div class="list-item"><div class="body">' + esc(arr[i]) + '</div></div>'; return out || '<div class="body">暂无内容</div>'; }
    if(id === 'work-cockpit') {
      var topics=(daily.news_topics||[]).slice(0,4);
      var alertRows='';
      for(var aj=0;aj<Math.min(alerts.length,3);aj++){
        alertRows += '<div class="list-item" style="padding:0 0 14px 0;border-bottom:1px solid rgba(148,163,184,.12)"><div class="body" style="font-size:26px;line-height:1.18">' + esc(alerts[aj].title || '提醒') + '</div><div class="tiny row" style="font-size:19px;line-height:1.35;color:rgba(226,232,240,.72)">' + esc(alerts[aj].body || '') + '</div></div>';
      }
      return '<div class="screen active">'
        + '<div class="launch-shell flyin-curtain flyin-stagger-1">'
          + '<div class="launch-grid">'
            + '<div class="launch-copy">'
              + '<div>'
                + '<div class="launch-kicker motion-slide-down">Remote Panel · Dynamic Start</div>'
                + '<div class="launch-title motion-title-float">MISSION<span class="accent">CONTROL</span></div>'
                + '<div class="launch-subcopy motion-slide-up">' + esc(wk.current_task || '等待任务') + ' —— ' + esc(wk.summary || '暂无任务摘要') + '</div>'
                + '<div class="launch-badges">'
                  + '<span class="launch-badge">Host ' + esc(ops.host || '--') + '</span>'
                  + '<span class="launch-badge">CPU ' + esc(ops.cpu_pct) + '%</span>'
                  + '<span class="launch-badge">MEM ' + esc(ops.mem_pct) + '%</span>'
                  + '<span class="launch-badge">Alerts ' + esc(alerts.length || 0) + '</span>'
                + '</div>'
                + '<div class="launch-stats">'
                  + '<div class="launch-stat"><div class="k">Next Action</div><div class="v">' + esc(wk.next_task || '继续当前项') + '</div><div class="d">唯一主指令，直接开干</div></div>'
                  + '<div class="launch-stat"><div class="k">System Live</div><div class="v">' + esc(ops.cpu_pct) + '%</div><div class="d">CPU 负载 · MEM ' + esc(ops.mem_pct) + '%</div></div>'
                  + '<div class="launch-stat"><div class="k">Signal</div><div class="v">' + esc(alerts.length || 0) + '</div><div class="d">提醒与关注点</div></div>'
                + '</div>'
              + '</div>'
              + '<div>'
                + '<div class="row" style="padding:0;background:none;border:none">' + badgeRow(topics, 'cyan') + '</div>'
                + '<div class="quote" style="margin-top:18px;background:rgba(15,23,42,.24);border:1px solid rgba(255,255,255,.10)">' + esc(daily.quote || '继续推进今日重点。') + '</div>'
              + '</div>'
            + '</div>'
            + '<div class="launch-visual flyin-right flyin-stagger-2">'
              + '<div class="launch-orbit motion-orbit">'
                + '<div class="launch-ring r1"></div>'
                + '<div class="launch-ring r2"></div>'
                + '<div class="launch-ring r3"></div>'
                + '<div class="launch-core motion-pulse-glow"><div class="launch-core-label">Live State</div><div class="launch-core-value">GO</div><div class="launch-core-meta">任务执行中 / 实时联动</div></div>'
              + '</div>'
              + '<div class="launch-float f1"><div class="t">Host</div><div class="v">' + esc(ops.host || '--') + '</div><div class="m">控制面板节点</div></div>'
              + '<div class="launch-float f2"><div class="t">Disk</div><div class="v">' + esc(ops.disk_pct) + '%</div><div class="m">磁盘占用</div></div>'
              + '<div class="launch-float f3"><div class="t">Session</div><div class="v">' + esc((sess.summary || 'LIVE').slice(0, 10)) + '</div><div class="m">' + esc(sess.summary || '暂无摘要').slice(0,28) + '</div></div>'
              + '<div class="launch-float f4"><div class="t">Action</div><div class="v">' + esc((wk.next_task || '继续').slice(0, 10)) + '</div><div class="m">下一动作</div></div>'
            + '</div>'
          + '</div>'
        + '</div>'
        + '<div class="two-col row flyin-up flyin-stagger-3" style="grid-template-columns:.92fr 1.08fr;align-items:stretch;gap:22px;margin-top:22px">'
          + '<div class="card" style="padding:28px;background:linear-gradient(180deg, rgba(8,47,73,.86), rgba(15,23,42,.96));border-color:rgba(125,211,252,.18)"><div class="label" style="font-size:20px">Alert Feed</div>' + (alertRows || '<div class="small row" style="font-size:24px">暂无提醒</div>') + '</div>'
          + '<div class="card dark" style="padding:28px;background:linear-gradient(180deg, rgba(15,23,42,.96), rgba(30,41,59,.90));border-color:rgba(148,163,184,.14)"><div class="label" style="font-size:20px">Conversation Summary</div><div class="mid row" style="font-size:38px;line-height:1.16;margin-top:10px">' + esc(sess.summary || '暂无摘要') + '</div><div class="small row" style="font-size:22px;line-height:1.34;margin-top:18px">会话摘要保留在启动页底部整块区域，主视觉改成更强烈的动态指挥台。</div></div>'
        + '</div>'
        + '</div>';
    }
    if(id === 'chat-stream') {
      return '<div class="screen active">'
        + '<div class="card flyin-down flyin-stagger-1"><div class="label">Merged Into Cockpit</div><div class="big row">对话流已并入工作作战台</div><div class="small row">最近对话、摘要、Focus/Next 已在工作作战台统一展示。</div></div>'
        + '</div>';
    }
    if(id === 'alerts') {
      return '<div class="screen active">'
        + '<div class="card flyin-zoom flyin-stagger-1"><div class="label">Merged Into Cockpit</div><div class="big row">提醒栈已并入工作作战台</div><div class="small row">Alert digest 与处理建议已合并展示，避免与工作作战台重复。</div></div>'
        + '</div>';
    }
    if(id === 'penguin-balance') {
      var pg = state.penguin || {};
      var pgDays = pg.history_days || [];
      var pgModels = pg.history_models || [];
      var dayBars = '';
      var maxDay = 0;
      for(var pdi=0; pdi<pgDays.length; pdi++) maxDay = Math.max(maxDay, Number(pgDays[pdi].usageUsd || 0));
      for(var pd=0; pd<Math.min(pgDays.length, 7); pd++) {
        var item = pgDays[pd] || {};
        var pct = maxDay > 0 ? Math.max(10, Math.round((Number(item.usageUsd || 0) / maxDay) * 100)) : 12;
        dayBars += '<div style="display:grid;grid-template-columns:92px 1fr 120px;gap:16px;align-items:center;padding:10px 0;border-top:' + (pd ? '1px solid rgba(255,255,255,.08)' : '0') + '"><div style="font-size:18px;color:rgba(255,255,255,.72)">' + esc(String(item.date || '').slice(5).replace('-', '/')) + '</div><div style="height:14px;border-radius:999px;background:rgba(255,255,255,.10);overflow:hidden"><div style="width:' + pct + '%;height:100%;background:linear-gradient(90deg,#38bdf8,#f472b6,#fbbf24);box-shadow:0 0 16px rgba(244,114,182,.22)"></div></div><div style="font-size:24px;font-weight:800;text-align:right">$' + esc(item.usageUsd != null ? Number(item.usageUsd).toFixed(2) : '--') + '</div></div>';
      }
      var modelRows = '';
      for(var pm=0; pm<Math.min(pgModels.length, 5); pm++) {
        var model = pgModels[pm] || {};
        modelRows += '<div class="list-item"><div class="body" style="display:flex;justify-content:space-between;gap:14px"><span style="max-width:68%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(model.model || 'unknown') + '</span><span style="font-weight:800;color:#fbcfe8">$' + esc(model.usageUsd != null ? Number(model.usageUsd).toFixed(2) : '--') + '</span></div><div class="tiny row" style="font-size:17px;color:rgba(255,255,255,.64)">' + esc(model.requests != null ? model.requests : '--') + ' requests</div></div>';
      }
      return '<div class="screen active">'
        + '<div class="two-col row flyin-curtain flyin-stagger-1" style="grid-template-columns:1.18fr .82fr;align-items:stretch;gap:22px">'
          + '<div class="card hero-card" style="padding:34px;min-height:720px;background:linear-gradient(135deg, rgba(15,23,42,.96), rgba(91,33,182,.28) 40%, rgba(236,72,153,.22) 72%, rgba(14,165,233,.18));border-color:rgba(244,114,182,.26)">'
            + '<div class="label" style="font-size:20px;letter-spacing:.16em;color:#fbcfe8">企鹅余额</div>'
            + '<div class="small row" style="font-size:22px;color:rgba(255,255,255,.76);margin-top:14px">' + esc(pg.username || '') + (pg.group ? ' · ' + esc(pg.group) : '') + '</div>'
            + '<div class="small row" style="font-size:20px;color:rgba(255,255,255,.56);margin-top:8px">' + esc(pg.queried_at || '') + '</div>'
            + '<div class="small row" style="font-size:20px;color:#fda4af;margin-top:10px">' + esc(pg.error || '') + '</div>'
            + '<div style="margin-top:26px;font-size:24px;letter-spacing:.22em;text-transform:uppercase;color:#f9a8d4">剩余额度</div>'
            + '<div class="huge row motion-pulse-glow" style="font-size:120px;line-height:.92;letter-spacing:-.03em;margin-top:12px;color:#fff;text-shadow:0 0 30px rgba(244,114,182,.20);white-space:nowrap;overflow:hidden;text-overflow:clip">' + esc(pg.balance_usd != null ? Number(pg.balance_usd).toFixed(2) : '--') + '</div>'
            + '<div class="mid row" style="font-size:38px;line-height:1.12;color:#fde7f3;margin-top:10px">人民币 ¥ ' + esc(pg.balance_cny != null ? Number(pg.balance_cny).toFixed(2) : '--') + '</div>'
            + '<div class="launch-badges" style="margin-top:22px"><span class="launch-badge">今日 $' + esc(pg.today_usd != null ? Number(pg.today_usd).toFixed(2) : '--') + '</span><span class="launch-badge">24小时 $' + esc(pg.last24_usd != null ? Number(pg.last24_usd).toFixed(2) : '--') + '</span><span class="launch-badge">本月 $' + esc(pg.month_usd != null ? Number(pg.month_usd).toFixed(2) : '--') + '</span></div>'
            + '<div class="launch-stats" style="margin-top:26px;grid-template-columns:repeat(2,minmax(0,1fr))"><div class="launch-stat"><div class="k">预计可用</div><div class="v" style="font-size:38px">' + esc(pg.days_remaining != null ? pg.days_remaining : '--') + '</div><div class="d">天数</div></div><div class="launch-stat"><div class="k">请求总数</div><div class="v" style="font-size:38px">' + esc(pg.request_count != null ? pg.request_count : '--') + '</div><div class="d">累计请求</div></div><div class="launch-stat"><div class="k">RPM</div><div class="v" style="font-size:38px">' + esc(pg.rpm != null ? pg.rpm : '--') + '</div><div class="d">今日速率</div></div><div class="launch-stat"><div class="k">TPM</div><div class="v" style="font-size:38px">' + esc(pg.tpm != null ? pg.tpm : '--') + '</div><div class="d">令牌速率</div></div></div>'
          + '</div>'
          + '<div class="stack-14">'
            + '<div class="card dark flyin-right flyin-stagger-2" style="background:linear-gradient(180deg, rgba(15,23,42,.96), rgba(30,41,59,.86));border-color:rgba(125,211,252,.18)"><div class="label">7日消耗趋势</div>' + (dayBars || '<div class="body">暂无历史数据</div>') + '</div>'
            + '<div class="card dark flyin-up flyin-stagger-3" style="background:linear-gradient(180deg, rgba(17,24,39,.96), rgba(76,29,149,.24));border-color:rgba(244,114,182,.18)"><div class="label">模型消费排行</div>' + (modelRows || '<div class="body">暂无模型消费数据</div>') + '</div>'
          + '</div>'
        + '</div>'
        + '<div class="two-col row flyin-up flyin-stagger-4" style="grid-template-columns:1fr 1fr;gap:22px;margin-top:22px"><div class="card"><div class="label">Balance Quota</div><div class="big row">' + esc(pg.balance_quota != null ? pg.balance_quota : '--') + '</div><div class="small row">原始 quota 余额</div></div><div class="card dark"><div class="label">Total Used</div><div class="big row">$' + esc(pg.total_used_usd != null ? Number(pg.total_used_usd).toFixed(2) : '--') + '</div><div class="small row">累计消耗</div></div></div>'
        + '</div>';
    }
    if(id === 'schedule-board') {
      var agenda = state.schedule || {};
      var todayItems = agenda.today || [];
      var weekItems = agenda.week || [];
      function dayLabel(dateStr){
        try {
          var d = new Date(dateStr + 'T00:00:00');
          var names = ['周日','周一','周二','周三','周四','周五','周六'];
          return names[d.getDay()];
        } catch(_e) {
          return '--';
        }
      }
      function dateShort(dateStr){
        if(!dateStr) return '--';
        return dateStr.slice(5).replace('-', '/');
      }
      function priorityTag(priority){
        if(priority === 'high') return 'HIGH';
        if(priority === 'low') return 'LOW';
        return 'PLAN';
      }
      function priorityColor(priority){
        if(priority === 'high') return '#fb7185';
        if(priority === 'low') return '#34d399';
        return '#fbbf24';
      }
      var allItems = weekItems.slice(0, 12);
      var nowLead = todayItems[0] || weekItems[0] || null;
      var timelineBlocks = allItems.map(function(item, index){
        var isToday = todayItems.some(function(t){ return t.id === item.id; });
        var accent = priorityColor(item.priority);
        var h = isToday && index === 0 ? 280 : (index < 3 ? 208 : 166);
        var extra = isToday ? 'box-shadow:0 0 0 2px rgba(255,255,255,.10) inset, 0 28px 60px rgba(0,0,0,.30);' : 'box-shadow:0 16px 36px rgba(0,0,0,.22);';
        return '<div class="flyin-up flyin-stagger-' + ((index % 4) + 1) + '" style="position:relative;margin-left:' + (isToday ? 0 : 42) + 'px;margin-bottom:18px">'
          + '<div style="position:absolute;left:-42px;top:' + (isToday ? 28 : 18) + 'px;width:18px;height:18px;border-radius:999px;background:' + accent + ';box-shadow:0 0 22px ' + accent + ';border:3px solid rgba(255,255,255,.22)"></div>'
          + '<div style="position:absolute;left:-33px;top:' + (isToday ? 46 : 36) + 'px;bottom:-20px;width:2px;background:linear-gradient(180deg,' + accent + ', rgba(255,255,255,.04))"></div>'
          + '<div style="min-height:' + h + 'px;padding:24px 26px 22px 26px;border-radius:34px;background:linear-gradient(135deg, ' + accent + '33, rgba(15,23,42,.92) 48%, rgba(17,24,39,.96));border:1px solid ' + accent + '66;' + extra + '">'
            + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:14px"><div><div style="font-size:18px;letter-spacing:.18em;text-transform:uppercase;color:' + accent + ';font-weight:700">' + esc(priorityTag(item.priority)) + ' · ' + esc(dayLabel(item.date)) + '</div><div style="font-size:' + (isToday && index === 0 ? 72 : 52) + 'px;line-height:.9;font-weight:900;color:#fff;margin-top:8px">' + esc(item.time || '全天') + '</div></div><div style="padding:8px 14px;border-radius:999px;background:rgba(255,255,255,.08);font-size:22px;color:#fff">' + esc(dateShort(item.date)) + '</div></div>'
            + '<div style="font-size:' + (isToday && index === 0 ? 44 : 34) + 'px;line-height:1.04;font-weight:850;color:#fff;margin-top:14px;max-width:94%">' + esc(item.title || '未命名事项') + '</div>'
            + '<div style="font-size:' + (isToday && index === 0 ? 24 : 20) + 'px;line-height:1.34;color:rgba(255,255,255,.80);margin-top:14px;max-width:96%">' + esc(item.notes || '等待补充说明') + '</div>'
            + (isToday ? '<div style="display:flex;gap:12px;align-items:center;margin-top:18px"><div style="height:12px;flex:1;border-radius:999px;background:rgba(255,255,255,.10);overflow:hidden"><div style="width:68%;height:100%;background:linear-gradient(90deg,' + accent + ', #fff);box-shadow:0 0 18px ' + accent + '"></div></div><div style="font-size:18px;letter-spacing:.18em;color:rgba(255,255,255,.72)">TODAY FOCUS</div></div>' : '')
          + '</div></div>';
      }).join('');
      if(!timelineBlocks) timelineBlocks = '<div class="flyin-up flyin-stagger-1" style="margin-left:42px"><div style="position:absolute"></div><div style="padding:28px 30px;border-radius:34px;background:linear-gradient(135deg, rgba(56,189,248,.24), rgba(129,140,248,.12) 50%, rgba(15,23,42,.94));border:1px solid rgba(125,211,252,.30);box-shadow:0 18px 42px rgba(0,0,0,.24)"><div style="font-size:56px;line-height:.96;font-weight:900;color:#fff">本周空档</div><div style="font-size:26px;line-height:1.34;color:rgba(255,255,255,.82);margin-top:16px">你之后只要说“增加一个日程：……” 我就会同步写进这里。</div></div></div>';
      var weekGroups = {};
      for(var wi=0; wi<weekItems.length; wi++){
        var item = weekItems[wi] || {};
        var key = String(item.date || '');
        if(!weekGroups[key]) weekGroups[key] = [];
        weekGroups[key].push(item);
      }
      var stripKeys = Object.keys(weekGroups).slice(0,7);
      var weekStrip = stripKeys.map(function(key, idx){
        var list = weekGroups[key] || [];
        var accent = ['#fb7185','#38bdf8','#fbbf24','#34d399','#a78bfa','#fb923c','#22c55e'][idx % 7];
        var top = list[0] || {};
        return '<div class="flyin-right flyin-stagger-' + ((idx % 4) + 1) + '" style="padding:18px 18px 20px;border-radius:28px;background:linear-gradient(180deg, ' + accent + '2c, rgba(15,23,42,.92));border:1px solid ' + accent + '55;min-height:210px;box-shadow:0 16px 34px rgba(0,0,0,.20)">'
          + '<div style="font-size:18px;letter-spacing:.14em;text-transform:uppercase;color:' + accent + ';font-weight:700">' + esc(dayLabel(key)) + '</div>'
          + '<div style="font-size:36px;line-height:1.0;font-weight:900;color:#fff;margin-top:8px">' + esc(dateShort(key)) + '</div>'
          + '<div style="font-size:17px;color:rgba(255,255,255,.72);margin-top:6px">' + esc(list.length) + ' 个安排</div>'
          + '<div style="font-size:24px;line-height:1.14;font-weight:760;color:#fff;margin-top:16px">' + esc(top.time || '全天') + ' · ' + esc(top.title || '未命名事项') + '</div>'
          + '<div style="font-size:17px;line-height:1.28;color:rgba(255,255,255,.74);margin-top:10px">' + esc(top.notes || '') + '</div>'
        + '</div>';
      }).join('');
      if(!weekStrip) weekStrip = '<div class="flyin-right flyin-stagger-2" style="padding:20px;border-radius:28px;background:linear-gradient(180deg, rgba(56,189,248,.20), rgba(15,23,42,.92));border:1px solid rgba(125,211,252,.24)"><div style="font-size:28px;color:#fff">未来 7 天暂无日程</div></div>';
      var topMeta = nowLead
        ? '<div class="flyin-down flyin-stagger-1" style="display:grid;grid-template-columns:1.05fr .95fr;gap:18px;align-items:end;margin-bottom:24px"><div><div style="font-size:22px;letter-spacing:.24em;text-transform:uppercase;color:#f9a8d4;font-weight:700">AGENDA STREAM</div><div style="font-size:88px;line-height:.88;font-weight:900;color:#fff;margin-top:10px">今天 + 未来七天</div><div style="font-size:28px;line-height:1.24;color:rgba(255,255,255,.78);margin-top:14px;max-width:88%">以时间流作为主轴，左边看现在与下一步，右边看整周密度与节奏。</div></div><div style="display:flex;justify-content:flex-end;gap:16px"><div style="padding:18px 20px;border-radius:24px;background:linear-gradient(180deg, rgba(251,113,133,.18), rgba(15,23,42,.88));border:1px solid rgba(251,113,133,.28);min-width:190px"><div style="font-size:18px;letter-spacing:.14em;color:#fda4af">TODAY</div><div style="font-size:64px;line-height:.9;font-weight:900;color:#fff;margin-top:8px">' + esc(todayItems.length) + '</div></div><div style="padding:18px 20px;border-radius:24px;background:linear-gradient(180deg, rgba(56,189,248,.18), rgba(15,23,42,.88));border:1px solid rgba(125,211,252,.28);min-width:190px"><div style="font-size:18px;letter-spacing:.14em;color:#7dd3fc">THIS WEEK</div><div style="font-size:64px;line-height:.9;font-weight:900;color:#fff;margin-top:8px">' + esc(weekItems.length) + '</div></div></div></div>'
        : '<div class="flyin-down flyin-stagger-1" style="margin-bottom:24px"><div style="font-size:22px;letter-spacing:.24em;text-transform:uppercase;color:#f9a8d4;font-weight:700">AGENDA STREAM</div><div style="font-size:88px;line-height:.88;font-weight:900;color:#fff;margin-top:10px">未来日程</div></div>';
      return '<div class="screen active">'
        + '<div style="position:relative;min-height:1430px;padding:6px 0 0">'
          + '<div style="position:absolute;inset:140px 0 220px 120px;border-left:3px solid rgba(255,255,255,.10);opacity:.9"></div>'
          + '<div style="position:absolute;left:80px;top:240px;width:240px;height:240px;border-radius:999px;background:radial-gradient(circle, rgba(251,113,133,.22), rgba(251,113,133,0));filter:blur(8px)"></div>'
          + '<div style="position:absolute;right:60px;top:110px;width:300px;height:300px;border-radius:999px;background:radial-gradient(circle, rgba(56,189,248,.18), rgba(56,189,248,0));filter:blur(10px)"></div>'
          + topMeta
          + '<div style="display:grid;grid-template-columns:1.12fr .88fr;gap:26px;align-items:start">'
            + '<div><div style="font-size:18px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.62);margin:0 0 18px 42px">TODAY / UPCOMING TIMELINE</div>' + timelineBlocks + '</div>'
            + '<div><div style="position:sticky;top:0"><div style="font-size:18px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.62);margin-bottom:18px">WEEK STRIP</div><div style="display:grid;grid-template-columns:1fr;gap:16px">' + weekStrip + '</div></div></div>'
          + '</div>'
        + '</div>'
        + '</div>';
    }
    if(id === 'weather-today') {
      var city = esc(w.city || 'Shanghai');
      var desc = String(w.description || '天气');
      var warm = /(晴|sun|clear)/i.test(desc);
      var weekGrid='';
      var peakDay = weatherWeekly[0] || {};
      var weekSummary = [];
      var dayThemes = [
        'linear-gradient(180deg, rgba(56,189,248,.34), rgba(14,165,233,.12))',
        'linear-gradient(180deg, rgba(244,114,182,.30), rgba(236,72,153,.12))',
        'linear-gradient(180deg, rgba(251,191,36,.30), rgba(245,158,11,.12))',
        'linear-gradient(180deg, rgba(52,211,153,.30), rgba(16,185,129,.12))',
        'linear-gradient(180deg, rgba(129,140,248,.30), rgba(99,102,241,.12))',
        'linear-gradient(180deg, rgba(250,204,21,.24), rgba(168,85,247,.14))'
      ];
      var dayBorders = ['#7dd3fc','#f9a8d4','#fcd34d','#86efac','#a5b4fc','#f9a8d4'];
      for(var wi=0; wi<Math.min(weatherWeekly.length,6); wi++){
        var item = weatherWeekly[wi] || {};
        var hi = item.temp_max != null ? Number(item.temp_max) : null;
        var lo = item.temp_min != null ? Number(item.temp_min) : null;
        var spread = (hi != null && lo != null) ? Math.max(8, Math.min(100, Math.round((hi - lo) * 11 + 16))) : 42;
        if(hi != null && (peakDay.temp_max == null || hi > Number(peakDay.temp_max))) peakDay = item;
        if(item.description) weekSummary.push(item.weekday + ' ' + item.description);
        var theme = dayThemes[wi % dayThemes.length];
        var border = dayBorders[wi % dayBorders.length];
        weekGrid += '<div class="weather-day-card" style="background:' + theme + ';border-color:' + border + '55;box-shadow:0 18px 34px rgba(0,0,0,.20), inset 0 1px 0 rgba(255,255,255,.12)">'
          + '<div class="top"><div class="day">' + esc(item.weekday || '--') + '</div><div class="icon" style="color:' + border + '">' + esc(item.icon || '☁') + '</div></div>'
          + '<div class="high">' + esc(item.temp_max != null ? item.temp_max : '--') + '°</div>'
          + '<div class="low">Low ' + esc(item.temp_min != null ? item.temp_min : '--') + '°</div>'
          + '<div class="desc">' + esc(item.description || '暂无描述') + '</div>'
          + '<div class="bar" style="background:' + border + '22"><span style="width:' + spread + '%;background:linear-gradient(90deg,' + border + ', rgba(255,255,255,.96))"></span></div>'
          + '</div>';
      }
      var scene = '<div class="weather-scene">'
        + '<div class="weather-sun"></div>'
        + '<div class="weather-cloud c1"></div>'
        + '<div class="weather-cloud c2"></div>'
        + '<div class="weather-cloud c3"></div>'
        + '<div class="weather-foreground"></div>'
        + '<div class="weather-cityline"></div>'
        + '<div class="hero-overlay"><div class="headline" style="font-size:46px">' + city + ' · ' + esc(desc) + '</div><div class="meta" style="font-size:22px">最低 ' + esc(w.temp_min != null ? w.temp_min : '--') + '° / 最高 ' + esc(w.temp_max != null ? w.temp_max : '--') + '°</div></div>'
        + '</div>';
      return '<div class="screen active">'
        + '<div class="weather-grid"><div class="card hero-card motion-card-float-slow flyin-left flyin-stagger-1"><div class="hero-art">' + scene + '</div></div><div class="stack-14"><div class="card dark motion-card-float flyin-right flyin-stagger-2"><div class="label" style="font-size:20px">当前温度</div><div class="huge row motion-pulse-glow" style="font-size:168px">' + esc(w.temperature != null ? w.temperature : '--') + '°</div><div class="small row" style="font-size:22px">体感 ' + esc(w.feels_like != null ? w.feels_like : '--') + '° · 湿度 ' + esc(w.humidity != null ? w.humidity : '--') + '%</div><div class="small" style="font-size:22px">风速 ' + esc(w.wind_speed != null ? w.wind_speed : '--') + '</div><div class="row">' + (warm ? '<span class="badge gold">SUNNY GLOW</span>' : '<span class="badge cyan">SKY FLOW</span>') + '<span class="badge">LIVE</span><span class="badge">6-DAY</span></div></div><div class="mini-columns motion-orbit flyin-up flyin-stagger-3">' + '<div class="mini-card"><div class="title">Air</div><div class="value">' + esc(w.humidity != null ? w.humidity : '--') + '%</div><div class="desc">湿度 / 空气体感</div></div>' + '<div class="mini-card"><div class="title">Wind</div><div class="value">' + esc(w.wind_speed != null ? w.wind_speed : '--') + '</div><div class="desc">当前风速</div></div>' + '</div></div></div>'
        + '<div class="card row flyin-up flyin-stagger-4"><div class="label" style="font-size:20px">六日详细预报</div><div class="weather-week-grid">' + (weekGrid || '<div class="body">暂无天气数据</div>') + '</div></div>'
        + '<div class="weather-summary-grid flyin-up flyin-stagger-5"><div class="weather-summary-card"><div class="title">Week Outlook</div><div class="headline">' + esc((peakDay.weekday || '本周') + ' 最高 ' + (peakDay.temp_max != null ? peakDay.temp_max : '--') + '°') + '</div><div class="copy">' + esc(weekSummary.slice(0,4).join(' · ') || '未来几天趋势将在此显示。') + '</div><div class="mini">今日页面已合并一周趋势，不再单独轮播。</div></div><div class="weather-summary-card"><div class="title">Trend Note</div><div class="headline">' + esc(desc) + ' / ' + esc(w.temperature != null ? w.temperature : '--') + '°</div><div class="copy">昼夜温差与天气变化已展开到上方 6 张日卡，整页用于一屏看完本周节奏。</div><div class="mini">城市：' + city + ' · 风速 ' + esc(w.wind_speed != null ? w.wind_speed : '--') + ' · 湿度 ' + esc(w.humidity != null ? w.humidity : '--') + '%</div></div></div>'
        + '</div>';
    }
    if(id === 'weather-weekly') {
      var lead = weatherWeekly[0] || {};
      var weekTiles='';
      for(var k=0;k<Math.min(weatherWeekly.length,6);k++) weekTiles += featureTile(weatherWeekly[k].weekday || '--', (weatherWeekly[k].temp_max != null ? weatherWeekly[k].temp_max : '--') + '°', weatherWeekly[k].description || '', (weatherWeekly[k].temp_min != null ? weatherWeekly[k].temp_min : '--') + '°');
      return '<div class="screen active">'
        + '<div class="split-hero"><div class="card hero-card"><div class="hero-art"><img class="thumb tall" src="/assets/ipad/weather-hero.png" alt="weather"><div class="hero-overlay"><div class="headline">' + esc(w.city || 'Shanghai') + '</div><div class="meta">' + esc(lead.description || '多日天气趋势') + '</div></div></div></div><div class="stack-14"><div class="card dark"><div class="label">Weekly Peak</div><div class="huge row">' + esc(lead.temp_max != null ? lead.temp_max : '--') + '°</div><div class="small row">最低 ' + esc(lead.temp_min != null ? lead.temp_min : '--') + '° · ' + esc(lead.weekday || '--') + '</div></div><div class="feature-grid">' + weekTiles + '</div></div></div>'
        + '</div>';
    }
    if(id === 'system') {
      var trafficRows = '';
      for(var ti=0; ti<Math.min((ops.traffic_lines || []).length, 6); ti++){
        trafficRows += '<div class="list-item"><div class="body">' + esc(ops.traffic_lines[ti]) + '</div></div>';
      }
      var vpsTone = 'linear-gradient(135deg, rgba(250,204,21,.18), rgba(236,72,153,.16) 52%, rgba(99,102,241,.14))';
      return '<div class="screen active">'
        + '<div class="card flyin-curtain flyin-stagger-1"><div class="label">系统信息</div><div class="kpi-grid row motion-orbit">' + statChip('CPU', esc(ops.cpu_pct) + '%') + statChip('MEM', esc(ops.mem_pct) + '%') + statChip('DISK', esc(ops.disk_pct) + '%') + statChip('HOST', esc(ops.host || '--')) + '</div><div class="two-col row"><div class="card dark"><div class="label">System Snapshot</div><div class="mid row">' + esc(ops.host || '本机设备') + '</div><div class="small row">' + esc(ops.os || '系统版本未知') + ' · 热状态 ' + esc(ops.thermal_status || '未知') + '</div><div class="small row">在线状态：' + ((state.device || {}).device_online ? 'YES' : 'NO') + '</div></div><div class="stack-14">' + featureTile('Compute', '处理器负载', '实时展示 CPU 压力与持续工作状态', esc(ops.cpu_pct) + '%') + featureTile('Storage', '磁盘容量', '只保留磁盘使用率，不再和下半区重复', esc(ops.disk_pct) + '%') + '</div></div></div>'
        + '<div class="row" style="height:18px"></div>'
        + '<div class="card flyin-up flyin-stagger-2" style="background:' + vpsTone + ';border-color:rgba(251,191,36,.28)"><div class="label">VPS流量</div><div class="hero-split row"><div><div class="huge row motion-pulse-glow">' + esc(vps.percent != null ? vps.percent : '--') + '%</div>' + meter(vps.percent) + '<div class="small row">已用 ' + esc(vps.used || '--') + ' · 剩余 ' + esc(vps.remain || '--') + '</div><div class="small row">计费周期：' + esc(vps.cycle || '暂无') + '</div><div class="badges" style="margin-top:14px"><span class="badge gold">BANDWIDTH</span><span class="badge pink">VPS</span><span class="badge">LIVE</span></div></div><div class="stack-14"><div class="mini-columns" style="grid-template-columns:.85fr 1.15fr"><div class="mini-card glass-art"><div class="title">Used</div><div class="value">' + esc(vps.used || '--') + '</div><div class="desc">本周期累计用量</div></div><div class="mini-card" style="background:linear-gradient(180deg, rgba(244,114,182,.20), rgba(244,114,182,.08));border-color:rgba(244,114,182,.32);box-shadow:0 0 0 1px rgba(255,255,255,.05) inset, 0 20px 40px rgba(244,114,182,.16)"><div class="title" style="font-size:20px;color:#fbcfe8">Remain</div><div class="value motion-pulse-glow" style="font-size:72px;line-height:.88;color:#fff;text-shadow:0 0 22px rgba(244,114,182,.28)">' + esc(vps.remain || '--') + '</div><div class="desc" style="font-size:22px;color:#ffe4ef">剩余额度</div></div></div><div class="card dark tight" style="background:rgba(15,23,42,.42)"><div class="label">链路明细</div>' + (trafficRows || '<div class="small row">暂无链路数据</div>') + '</div></div></div></div>'
        + '</div>';
    }
    if(id === 'traffic') {
      return '<div class="screen active"><div class="card"><div class="label">Merged Into System</div><div class="big row">VPS流量已并入系统信息页</div><div class="small row">上半部分为系统信息，下半部分为 VPS 流量详细信息。</div></div></div>';
    }
    if(id === 'news') {
      var dailyList = news.daily || [];
      var dailyItems = news.daily_items || [];
      var helloList = news.hello || [];
      var ghList = news.github || [];
      var lead = dailyList[0] || '今日继续推进。';
      var leadItem = dailyItems[0] || {};
      var leadImg = leadItem.image_url || '';
      var leftList = '';
      var helloBlock = '';
      var ghBlock = '';
      for(var ni=1; ni<Math.min(dailyList.length,6); ni++){
        leftList += '<div class="list-item"><div class="body">' + esc(dailyList[ni]) + '</div></div>';
      }
      for(var hi=0; hi<Math.min(helloList.length,4); hi++){
        helloBlock += '<div class="list-item"><div class="body">' + esc(helloList[hi]) + '</div></div>';
      }
      for(var gi=0; gi<Math.min(ghList.length,4); gi++){
        ghBlock += '<div class="list-item"><div class="body">' + esc(ghList[gi]) + '</div></div>';
      }
      return '<div class="screen active">'
        + '<div class="feed-grid"><div class="card motion-card-float-slow flyin-curtain flyin-stagger-1"><div class="label">今日头条</div><div class="hero-split row"><div class="hero-art motion-image-drift-slow" style="min-height:360px">' + (leadImg ? '<img class="thumb medium" src="' + esc(leadImg) + '" alt="news">' : '<div class="news-art" style="min-height:360px"></div>') + '<div class="hero-overlay"><div class="headline">Cover Story</div><div class="meta">' + esc(leadItem.summary || daily.quote || '今日继续推进。') + '</div></div></div><div><div class="big row" style="font-size:54px;line-height:1.02">' + esc(lead) + '</div><div class="motion-slide-up row">' + (leftList || '<div class="body">暂无更多要闻</div>') + '</div></div></div></div><div class="stack-14"><div class="card dark hero-card flyin-right flyin-stagger-2"><div class="hero-art news-art"><div class="hero-overlay"><div class="headline">Daily Focus</div><div class="meta">' + esc(daily.quote || '今日继续推进。') + '</div></div></div></div><div class="card dark motion-card-float flyin-up flyin-stagger-3"><div class="label">HelloGitHub</div><div class="motion-slide-up">' + (helloBlock || '<div class="body">暂无 HelloGitHub</div>') + '</div></div></div></div>'
        + '<div class="two-col row flyin-up flyin-stagger-4"><div class="card tight"><div class="label">Topics</div><div class="row">' + badgeRow((daily.news_topics || []).slice(0,8), 'cyan') + '</div><div class="quote row">' + esc(daily.quote || '今日继续推进。') + '</div></div><div class="card tight dark"><div class="label">Open Source Radar</div>' + (ghBlock || '<div class="body">暂无开源动态</div>') + '</div></div>'
        + '</div>';
    }
    if(id === 'github') {
      return '<div class="screen active"><div class="card"><div class="label">Merged Into News</div><div class="big row">开发动态已并入今日要闻页</div><div class="small row">Open Source Radar 已在今日要闻页底部统一展示。</div></div></div>';
    }
    if(id === 'gamer520') {
      var games = gamer520.items || [];
      var leadGame = games[0] || {};
      var coverWall = '';
      var rankList = '';
      var ribbon = '';
      for(var gi=0; gi<Math.min(games.length,6); gi++){
        coverWall += '<div class="poster-card flyin-zoom flyin-stagger-' + Math.min(gi + 1,6) + '" style="background:linear-gradient(180deg, rgba(15,23,42,.98), rgba(30,41,59,.92));border:1px solid rgba(251,146,60,.18)">' + thumb(games[gi].image_url || '', 'gamewide') + '<div class="poster-caption" style="font-size:25px;line-height:1.16">' + esc(games[gi].title || 'Untitled') + '</div><div class="poster-date">NO.' + String(gi + 1).padStart(2, '0') + ' · PC PLAY</div></div>';
      }
      for(var gj=0; gj<Math.min(games.length,5); gj++){
        rankList += '<div class="list-item" style="padding:14px 0;border-bottom:1px solid rgba(148,163,184,.14)"><div class="tiny row" style="font-size:16px;letter-spacing:.18em;color:rgba(251,191,36,.9)">TOP ' + String(gj + 1).padStart(2, '0') + '</div><div class="body" style="font-size:25px;line-height:1.18;margin-top:6px">' + esc(games[gj].title || 'Untitled') + '</div></div>';
      }
      for(var gk=5; gk<Math.min(games.length,10); gk++){
        ribbon += '<span class="badge" style="margin-right:10px;margin-bottom:10px;background:rgba(15,23,42,.55);border-color:rgba(251,146,60,.22)">' + esc(games[gk].title || 'Untitled') + '</span>';
      }
      return '<div class="screen active">'
        + '<div class="row" style="display:grid;grid-template-columns:1.24fr .76fr;gap:22px;align-items:stretch">'
          + '<div class="card flyin-curtain flyin-stagger-1" style="padding:26px 24px 24px 24px;background:linear-gradient(180deg, rgba(38,12,4,.94), rgba(15,23,42,.96));border-color:rgba(251,146,60,.22)"><div class="label" style="font-size:20px">Cover Wall · Page 1</div><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-top:16px">' + (coverWall || '<div class="body">暂无游戏数据</div>') + '</div></div>'
          + '<div style="display:grid;grid-template-rows:420px 1fr;gap:22px">'
            + '<div class="card hero-card flyin-right flyin-stagger-2" style="padding:30px;background:linear-gradient(180deg, rgba(20,20,33,.98), rgba(54,24,10,.92));border-color:rgba(251,191,36,.22)"><div class="label" style="font-size:20px">今日头条</div><div class="big row motion-title-float" style="font-size:60px;line-height:.98;margin-top:12px">GAMER520</div><div class="mid row" style="font-size:36px;line-height:1.1;margin-top:14px">' + esc(leadGame.title || 'PC PLAY 首屏同步') + '</div><div class="small row" style="font-size:22px;line-height:1.34;margin-top:16px">每天刷新一次，只同步第一页的游戏封面和标题。这个页面更像一面游戏上新情报墙，而不是 Steam 推荐页。</div><div class="row" style="margin-top:18px"><span class="badge gold motion-pulse-glow">' + esc(games.length) + ' ITEMS</span><span class="badge pink motion-pulse-glow">DAILY REFRESH</span><span class="badge">PC PLAY</span></div><div class="tiny row" style="margin-top:18px">更新时间 ' + esc((gamer520.updated_at || '').replace('T',' ').slice(0,16) || '--') + '</div></div>'
            + '<div class="card dark flyin-up flyin-stagger-3" style="padding:26px;background:linear-gradient(180deg, rgba(15,23,42,.98), rgba(30,41,59,.92));border-color:rgba(148,163,184,.14)"><div class="label" style="font-size:20px">Title Radar</div><div class="row" style="margin-top:12px">' + (rankList || '<div class="body">暂无标题列表</div>') + '</div><div class="label" style="font-size:18px;margin-top:18px">More Titles</div><div class="row" style="margin-top:12px;display:flex;flex-wrap:wrap">' + (ribbon || '<span class="small row">暂无更多标题</span>') + '</div><div class="tiny row" style="margin-top:16px">Source · https://www.gamer520.com/pcplay</div></div>'
          + '</div>'
        + '</div>'
        + '</div>';
    }
    if(id === 'steam') {
      var items=(steam.new_releases||[]).concat(steam.top_sellers||[]);
      var main = items[0] || {};
      var heroArt = main.header_url || main.capsule_url || main.screenshot_url || '';
      var grid='';
      var extra='';
      for(var s=1;s<Math.min(items.length,5);s++){
        var art = items[s].header_url || items[s].capsule_url || items[s].screenshot_url || '';
        grid += '<div class="poster-card">' + thumb(art, 'gamewide') + '<div class="poster-caption">' + esc(items[s].title || 'Untitled') + '</div><div class="poster-date">' + esc(items[s].subtitle || items[s].summary || '') + '</div></div>';
      }
      for(var s2=5;s2<Math.min(items.length,7);s2++){
        extra += '<div class="list-item"><div class="body">' + esc(items[s2].title || 'Untitled') + '</div><div class="tiny row">' + esc(items[s2].subtitle || items[s2].summary || '') + '</div></div>';
      }
      return '<div class="screen active">'
        + '<div class="split-hero"><div class="card hero-card flyin-left flyin-stagger-1"><div class="hero-art motion-image-drift-slow">' + thumb(heroArt, 'medium') + '<div class="hero-overlay"><div class="headline motion-title-float">' + esc(main.title || 'Steam 新游 & 热销') + '</div><div class="meta motion-slide-up">' + esc(main.subtitle || main.summary || '本周主打推荐') + '</div></div></div></div><div class="stack-14"><div class="card dark flyin-right flyin-stagger-2"><div class="label">Storefront Pick</div><div class="mid row">' + esc(main.title || 'Steam 新游 & 热销') + '</div><div class="small row">' + esc(main.subtitle || main.summary || '暂无游戏数据') + '</div><div class="row"><span class="badge gold motion-pulse-glow">HOT</span><span class="badge cyan motion-pulse-glow">NEW</span><span class="badge">精选</span></div></div><div class="mini-columns flyin-right flyin-stagger-3"><div class="mini-card"><div class="title">板块</div><div class="value">STEAM</div><div class="desc">新游 / 热销 / 视觉焦点</div></div><div class="mini-card"><div class="title">数量</div><div class="value">' + esc(items.length) + '</div><div class="desc">本轮可见条目</div></div></div></div></div>'
        + '<div class="feature-grid row flyin-up flyin-stagger-4">' + grid + '</div>'
        + '<div class="card tight flyin-up flyin-stagger-5"><div class="label">More Picks</div>' + (extra || '<div class="small row">暂无更多推荐</div>') + '</div>'
        + '</div>';
    }
    if(id === 'movies') {
      var lead = movies[0] || {};
      var posters='';
      for(var m=0;m<Math.min(movies.length,6);m++) posters += '<div class="poster-card flyin-zoom flyin-stagger-' + (Math.min(m+1,6)) + '">' + thumb(movies[m].poster_url || '', 'poster') + '<div class="poster-caption">' + esc(movies[m].title || 'Untitled') + '</div><div class="poster-date">上映 ' + esc(movies[m].release_date || '') + '</div></div>';
      return '<div class="screen active">'
        + '<div class="split-hero"><div class="card hero-card flyin-rotate-left flyin-stagger-1"><div class="hero-art motion-image-drift-slow">' + thumb(lead.poster_url || '', 'cinema') + '<div class="hero-overlay"><div class="headline motion-title-float">' + esc(lead.title || '正在热映') + '</div><div class="meta motion-slide-up">上映 ' + esc(lead.release_date || '') + '</div></div></div></div><div class="card dark flyin-rotate-right flyin-stagger-2"><div class="label">Cinema Focus</div><div class="mid row motion-ticker">' + esc(lead.title || '本周焦点') + '</div><div class="body row">' + esc(lead.overview || '暂无影讯') + '</div><div class="row"><span class="badge gold motion-pulse-glow">Now Showing</span><span class="badge pink motion-pulse-glow">Featured</span></div></div></div>'
        + '<div class="poster-grid row">' + posters + '</div>'
        + '</div>';
    }
    if(id === 'print-ops') {
      var ams = pr.ams || [];
      var items = [];
      var printers = (state.print && state.print.printers) || [];
      var nozzleList = ((pr.temps || {}).nozzles || []).filter(function(n){ return n; });
      function colorList(bound, slot){
        var out = [];
        var src = [];
        if(bound && bound.colors && bound.colors.length) src = src.concat(bound.colors);
        if(slot && slot.colors && slot.colors.length) src = src.concat(slot.colors);
        if(bound && bound.colorHex) src.push(bound.colorHex);
        if(slot && slot.colorHex) src.push(slot.colorHex);
        for(var ci=0; ci<src.length; ci++){
          var raw = String(src[ci] || '').trim();
          if(!raw) continue;
          if(raw[0] !== '#') raw = '#' + raw;
          if(out.indexOf(raw) < 0) out.push(raw);
        }
        return out.slice(0, 4);
      }
      function pctLabel(v){ return (v != null && v !== '' ? Math.round(num(v, 0)) + '%' : '--'); }
      function tempLabel(v){ return (v != null && v !== '' ? Math.round(num(v, 0)) + '°' : '--'); }
      function minsLabel(v){ return (v != null && v !== '' ? Math.round(num(v, 0)) + 'm' : '--'); }
      function gramsLabel(v){ return (v != null && v !== '' ? Math.round(num(v, 0)) + 'g' : '--'); }
      var lowStock = [];
      var materialTypes = {};
      var onlinePrinters = 0;
      for(var ai=0; ai<ams.length; ai++){
        var unit = ams[ai] || {};
        var slots = unit.slots || [];
        for(var si=0; si<slots.length; si++){
          var slot = slots[si] || {};
          var bound = slot.bound || {};
          var pct = bound.remainingPercent != null ? bound.remainingPercent : slot.remainPercent;
          var grams = bound.remainingGram != null ? Math.round(num(bound.remainingGram, 0)) : null;
          var totalGram = bound.totalGram != null ? Math.round(num(bound.totalGram, 0)) : null;
          var item = {
            tray:'AMS ' + (ai + 1) + '-' + (si + 1),
            amsLabel:(unit.type || 'AMS') + ' #' + (ai + 1),
            unitType:unit.type || 'AMS',
            name:bound.name || (slot.type ? slot.type + ' 材料' : '空槽位'),
            brand:bound.brand || '',
            type:bound.type || slot.type || '--',
            pct:pct != null ? Math.round(num(pct, 0)) : 0,
            grams:grams,
            totalGram:totalGram,
            colors:colorList(bound, slot),
            rainbow:!!bound.isRainbow,
            empty:!!slot.isEmpty
          };
          items.push(item);
          if(!item.empty){
            materialTypes[item.type] = true;
            if(item.pct <= 20) lowStock.push(item);
          }
        }
      }
      items.sort(function(a,b){ return (a.pct||0) - (b.pct||0); });
      for(var pi=0; pi<printers.length; pi++) if(printers[pi] && printers[pi].online) onlinePrinters += 1;
      var critical = lowStock.slice(0, 4);
      var inventory = items.slice(0, 6);
      var nozzleCards = nozzleList.slice(0, 2).map(function(n){
        return '<div class="mini-card" style="padding:20px 22px;background:linear-gradient(180deg, rgba(59,130,246,.14), rgba(15,23,42,.16));border-color:rgba(96,165,250,.20)"><div class="title">' + esc(n.name || '喷嘴') + '</div><div class="value">' + tempLabel(n.temp) + '</div><div class="desc">' + (n.active ? '工作中' : '待机中') + '</div></div>';
      }).join('');
      if(!nozzleCards) nozzleCards = '<div class="mini-card" style="padding:20px 22px"><div class="title">喷嘴阵列</div><div class="desc">暂无独立喷嘴温度</div></div>';
      var printerRows = printers.slice(0, 3).map(function(pp, idx){
        var progress = pp && pp.progress != null ? Math.round(num(pp.progress, 0)) : 0;
        return '<div class="mini-card" style="padding:18px 20px;background:linear-gradient(180deg, rgba(15,23,42,.88), rgba(30,41,59,.78));border-color:rgba(148,163,184,.14)"><div class="title">PRINTER ' + String(idx + 1).padStart(2,'0') + '</div><div class="desc" style="font-size:24px;line-height:1.18;color:#f8fafc">' + esc(pp.name || pp.model || 'Printer') + '</div><div class="desc" style="font-size:18px;line-height:1.28;margin-top:6px">' + esc(pp.statusText || pp.status || '--') + ' · ' + minsLabel(pp.remainingMinutes) + '</div><div class="bar" style="margin-top:12px"><span data-w="' + progress + '"></span></div><div class="desc" style="margin-top:8px">任务：' + esc(pp.fileName || '暂无任务') + '</div></div>';
      }).join('');
      if(!printerRows) printerRows = '<div class="mini-card" style="padding:20px 22px"><div class="title">Printer Fleet</div><div class="desc">暂无打印机列表</div></div>';
      var criticalRows = critical.length ? critical.map(function(it){
        var dots='';
        for(var di=0; di<it.colors.length; di++) dots += '<span class="color-dot" style="background:' + esc(it.colors[di]) + '"></span>';
        if(!dots) dots = '<span class="tiny muted">无颜色</span>';
        return '<div class="mini-card" style="padding:18px 20px;background:linear-gradient(180deg, rgba(127,29,29,.34), rgba(15,23,42,.82));border-color:rgba(251,113,133,.28)"><div class="title">Low Stock</div><div class="desc" style="font-size:24px;line-height:1.14;color:#fff">' + esc(it.tray) + ' · ' + esc(it.type) + '</div><div class="desc" style="font-size:19px;line-height:1.25;margin-top:6px">' + esc(it.name) + '</div><div class="color-row" style="margin-top:8px">' + dots + '</div><div class="desc" style="font-size:18px;line-height:1.24;margin-top:8px">' + esc(it.brand || '未标品牌') + ' · ' + pctLabel(it.pct) + ' · ' + gramsLabel(it.grams) + '</div></div>';
      }).join('') : '<div class="mini-card" style="padding:20px 22px"><div class="title">Low Stock</div><div class="desc">当前没有危险低料位。</div></div>';
      var invCards = inventory.length ? inventory.map(function(it){
        var dots='';
        for(var di=0; di<it.colors.length; di++) dots += '<span class="color-dot" style="background:' + esc(it.colors[di]) + '"></span>';
        if(!dots) dots = '<span class="tiny muted">无颜色</span>';
        var lowCls = it.pct <= 20 ? ' low-stock' : '';
        return '<div class="inv-card' + lowCls + '"><div class="inv-top">' + esc(it.tray) + ' · ' + esc(it.type) + '</div><div class="inv-name">' + esc(it.name) + '</div><div class="inv-meta">' + esc(it.brand || '未标品牌') + (it.rainbow ? ' · 渐变/彩虹' : '') + (it.empty ? ' · 空槽位' : '') + '</div><div class="color-row">' + dots + '</div>' + meter(it.pct) + '<div class="inv-pct">' + esc(it.pct) + '%</div><div class="tiny muted" style="margin-top:6px">' + gramsLabel(it.grams) + ' / ' + gramsLabel(it.totalGram) + '</div></div>';
      }).join('') : '<div class="body row">暂无耗材数据</div>';
      return '<div class="screen active">'
        + '<div class="row flyin-curtain flyin-stagger-1" style="display:grid;grid-template-columns:1.18fr .82fr;gap:22px;align-items:stretch">'
          + '<div style="display:grid;grid-template-rows:560px 300px 300px;gap:22px">'
            + '<div class="card hero-card" style="padding:34px 34px 30px 34px;background:linear-gradient(180deg, rgba(11,17,32,.98), rgba(17,24,39,.92) 56%, rgba(11,17,32,.98));border-color:rgba(56,189,248,.18);display:flex;flex-direction:column;justify-content:space-between">'
              + '<div><div class="label" style="font-size:20px;letter-spacing:.14em">PRINT MISSION</div><div class="big row motion-title-float" style="font-size:88px;line-height:.9;margin-top:10px">' + esc(pr.statusText || pr.status || 'IDLE') + '</div><div class="body row" style="font-size:30px;line-height:1.2;margin-top:16px;max-width:92%">' + esc(pr.fileName || '暂无任务') + '</div><div class="small row" style="font-size:22px;line-height:1.28;margin-top:14px">' + esc(pr.name || pr.model || 'Printer') + ' · ' + esc(pr.model || '--') + ' · ' + (pr.online ? '在线' : '离线') + '</div></div>'
              + '<div style="display:grid;grid-template-columns:280px 1fr;gap:24px;align-items:center;margin-top:20px"><div><div class="mini-card glass-art" style="padding:26px 24px;height:220px;display:flex;flex-direction:column;justify-content:center"><div class="title">任务进度</div><div class="value" style="font-size:96px;line-height:.84">' + esc(pr.progress != null ? Math.round(pr.progress) : '--') + '%</div><div class="desc">' + esc(pr.statusText || pr.status || 'IDLE') + '</div>' + meter(pr.progress) + '</div></div><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px">'
                + '<div class="mini-card glass-art" style="padding:20px 22px"><div class="title">层数</div><div class="value">' + esc(pr.layer != null ? pr.layer : '--') + '</div><div class="desc">/ ' + esc(pr.totalLayers != null ? pr.totalLayers : '--') + ' Layers</div></div>'
                + '<div class="mini-card" style="padding:20px 22px;background:linear-gradient(180deg, rgba(14,165,233,.18), rgba(15,23,42,.12));border-color:rgba(125,211,252,.18)"><div class="title">剩余时间</div><div class="value">' + minsLabel(pr.remainingMinutes) + '</div><div class="desc">任务剩余</div></div>'
                + '<div class="mini-card" style="padding:20px 22px"><div class="title">喷嘴规格</div><div class="value">' + esc(pr.nozzleDiameter != null ? pr.nozzleDiameter : '--') + '</div><div class="desc">mm nozzle</div></div>'
                + '<div class="mini-card" style="padding:20px 22px"><div class="title">耗材重量</div><div class="value">' + gramsLabel(pr.printWeightGram) + '</div><div class="desc">预计本次打印</div></div>'
              + '</div></div>'
            + '</div>'
            + '<div class="card flyin-up flyin-stagger-2" style="padding:26px;background:linear-gradient(180deg, rgba(8,47,73,.88), rgba(15,23,42,.94));border-color:rgba(96,165,250,.18)"><div class="label" style="font-size:20px">Thermals / Mechanics</div><div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-top:14px">'
              + '<div class="mini-card glass-art" style="padding:20px 22px"><div class="title">喷嘴</div><div class="value">' + tempLabel(pr.temps && pr.temps.nozzle) + '</div><div class="desc">主喷嘴实时温度</div></div>'
              + '<div class="mini-card" style="padding:20px 22px"><div class="title">热床</div><div class="value">' + tempLabel(pr.temps && pr.temps.bed) + '</div><div class="desc">Build plate</div></div>'
              + '<div class="mini-card" style="padding:20px 22px"><div class="title">腔体</div><div class="value">' + tempLabel(pr.temps && pr.temps.chamber) + '</div><div class="desc">Chamber</div></div>'
              + '<div class="mini-card" style="padding:20px 22px"><div class="title">在线打印机</div><div class="value">' + esc(onlinePrinters) + '</div><div class="desc">总数 ' + esc(printers.length || 0) + '</div></div>'
            + '</div></div>'
            + '<div class="card dark flyin-up flyin-stagger-3" style="padding:26px;background:linear-gradient(180deg, rgba(15,23,42,.96), rgba(30,41,59,.88));border-color:rgba(148,163,184,.14)"><div class="label" style="font-size:20px">Printer Fleet / Low Stock Radar</div><div style="display:grid;grid-template-columns:1.05fr .95fr;gap:14px;margin-top:14px"><div class="stack-14">' + printerRows + '</div><div class="stack-14">' + criticalRows + '</div></div></div>'
          + '</div>'
          + '<div class="card dark flyin-right flyin-stagger-4" style="padding:28px;background:linear-gradient(180deg, rgba(17,24,39,.96), rgba(15,23,42,.92));border-color:rgba(148,163,184,.14);display:flex;flex-direction:column"><div style="display:flex;justify-content:space-between;align-items:flex-end;gap:18px"><div><div class="label" style="font-size:20px">AMS / FILAMENT COMMAND WALL</div><div class="mid row" style="font-size:36px;line-height:1.08;margin-top:10px">所有可见料仓与耗材状态</div></div><div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;min-width:320px"><div class="mini-card" style="padding:16px 18px"><div class="title">AMS 单元</div><div class="value" style="font-size:38px">' + esc(ams.length) + '</div><div class="desc">含 HT / Pro</div></div><div class="mini-card" style="padding:16px 18px"><div class="title">槽位</div><div class="value" style="font-size:38px">' + esc(items.length) + '</div><div class="desc">全部可读槽位</div></div><div class="mini-card" style="padding:16px 18px"><div class="title">材料种类</div><div class="value" style="font-size:38px">' + esc(Object.keys(materialTypes).length) + '</div><div class="desc">当前载入类型</div></div></div></div><div class="inv-grid row" style="grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-top:20px;align-content:start">' + invCards + '</div></div>'
        + '</div>'
        + '</div>';
    }
    return '<div class="screen active"><div class="card"><div class="label">RemotePanel</div><div class="body row">空白屏</div></div></div>';
  }

  function settleEntranceAnimations(root){
    if(!root) return;
    var nodes = root.querySelectorAll('.flyin-left, .flyin-right, .flyin-up, .flyin-down, .motion-slide-up, .motion-slide-down');
    for(var i=0;i<nodes.length;i++){
      nodes[i].style.animation = 'none';
      nodes[i].style.opacity = '1';
      nodes[i].style.transform = 'translate3d(0,0,0) scale(1) rotate(0deg)';
    }
  }

  function fitScreenContent(){
    var viewport = el('viewport');
    if(!viewport) return;
    var screen = viewport.querySelector('.screen.active');
    if(!screen) return;
    screen.style.transform = '';
    screen.style.transformOrigin = 'top left';
    screen.style.width = '100%';
    var available = viewport.clientHeight;
    var needed = screen.scrollHeight;
    if(needed > available && available > 0){
      var scale = Math.max(.72, Math.min(1, available / needed));
      screen.style.transform = 'scale(' + scale + ')';
      screen.style.width = (100 / scale) + '%';
    }
  }

  function show(i, force, keepProgress, animateEntrance){
    idx = (i + order.length) % order.length;
    var id = order[idx];
    var cached = renderCache[id] || { html: renderScreen(id), sig: screenSignature(id) };
    var meta = metaMap[id] || {id:id,title:id,subtitle:'',family:'work'};
    var viewport = el('viewport');
    var nextHero = '<div class="kicker motion-slide-down">' + esc(meta.subtitle || '') + '</div><div class="title motion-title-float">' + esc(meta.title || meta.id) + '</div><div class="sub motion-slide-up">' + esc(heroSubcopy(id)) + '</div>';
    var sameScreen = viewport.getAttribute('data-screen-id') === id;
    var sameSig = viewport.getAttribute('data-screen-sig') === cached.sig;
    el('stage').className = familyToTheme(meta.family || 'work');
    if(force || !sameScreen || !sameSig){
      if(el('hero').innerHTML !== nextHero) el('hero').innerHTML = nextHero;
      viewport.innerHTML = cached.html;
      viewport.setAttribute('data-screen-id', id);
      viewport.setAttribute('data-screen-sig', cached.sig);
      if(!animateEntrance){
        settleEntranceAnimations(el('hero'));
        settleEntranceAnimations(viewport);
      }
    }
    dots();
    requestAnimationFrame(function(){
      fitScreenContent();
      setTimeout(fitScreenContent, 120);
      setTimeout(fitScreenContent, 600);
    });
    if(!keepProgress) resetProgress();
  }

  function next(){ show(idx+1, false, false, true); }

  function resetProgress(){
    progStart = Date.now();
    if(progTimer) clearInterval(progTimer);
    progTimer = setInterval(function(){ var p=(Date.now()-progStart)/dwell; if(p>=1){ el('progressFill').style.width='100%'; next(); return; } el('progressFill').style.width = Math.max(0, Math.min(100, p*100)) + '%'; }, 100);
  }
  function refresh(){
    fetch('/api/h5/state', {cache:'no-store'}).then(function(r){ return r.json(); }).then(function(data){
      if(!data || !data.screens) return;
      var nextSig = stableSignature(data);
      if(nextSig === lastRefreshSig){ el('status').textContent='LIVE'; return; }
      var currentId = order[idx] || order[0] || 'work-cockpit';
      lastRefreshSig = nextSig;
      state = data;
      metaMap = byIdMap();
      order = (state.screens||[]).map(function(s){ return s.id; });
      if(!order.length) order = ['work-cockpit'];
      dwell = Math.max(6000, Math.min(300000, num((state.template||{}).dwell_seconds, 60) * 1000));
      idx = order.indexOf(currentId);
      if(idx < 0) idx = 0;
      buildRenderCache();
      preloadImages(state);
      show(idx, true, true, false);
      el('status').textContent='LIVE';
    }).catch(function(){ el('status').textContent='STALE'; });
  }
  window.addEventListener('resize', function(){ fit(); fitScreenContent(); });
  buildRenderCache();
  preloadImages(state);
  tickClock(); setInterval(tickClock, 1000); fit(); show(idx, true, false, true); setInterval(refresh, 30000);
  el('stage').onclick = function(ev){ if(ev.clientX > window.innerWidth/2) next(); else show(idx-1, false, false, true); };
  var touchStartX = 0;
  var touchStartY = 0;
  el('stage').addEventListener('touchstart', function(ev){
    if(!ev.touches || !ev.touches.length) return;
    touchStartX = ev.touches[0].clientX;
    touchStartY = ev.touches[0].clientY;
  }, {passive:true});
  el('stage').addEventListener('touchend', function(ev){
    if(!ev.changedTouches || !ev.changedTouches.length) return;
    var dx = ev.changedTouches[0].clientX - touchStartX;
    var dy = ev.changedTouches[0].clientY - touchStartY;
    if(Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)){
      if(dx < 0) next(); else show(idx-1, false, false, true);
    }
  }, {passive:true});
})();
"""



