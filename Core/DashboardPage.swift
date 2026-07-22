import Foundation

/// Web dashboard served at GET / — the "notouch" Material design system
/// (imported from Claude Design) kept under the AgentGarden name: left sidebar,
/// top bar, hero approval card, agent fleet, and a live activity feed, in two
/// columns. Desktop-first with a responsive collapse for the phone. Wired live
/// to /agents · /approvals · /usage · /prompt · /approval/<id>/decide ·
/// /terminal · /keys.
enum DashboardPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="theme-color" content="#f4f9f5">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>AgentGarden</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&family=Roboto+Mono:wght@400;500&display=swap');
  :root {
    --font: 'Roboto', -apple-system, system-ui, 'Segoe UI', sans-serif;
    --mono: 'Roboto Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
    --ink: #202124; --muted: #5f6368; --faint: #9aa0a6;
    --blue: #1a73e8; --blue-d: #174ea6; --blue-soft: #e8f0fe;
    --red: #ea4335; --red-d: #c5221f; --red-soft: #fce8e6;
    --green: #34a853; --green-soft: #e6f4ea; --amber: #b06000; --amber-soft: #fef7e0;
    --line: #e0e2e6; --grey-soft: #f1f3f4; --side: #f4f9f5;
    --canvas: #e8eaed; --pill: 50px;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: var(--font); color: var(--ink); font-size: 15px; line-height: 1.5;
         -webkit-font-smoothing: antialiased; background: var(--canvas);
         background-image: radial-gradient(#d2d5db 1.2px, transparent 1.2px); background-size: 26px 26px; }

  .app { display: flex; min-height: 100vh; }

  /* sidebar */
  .sidebar { width: 236px; flex: none; background: var(--side); border-right: 1px solid var(--line);
             padding: 22px 16px calc(16px + env(safe-area-inset-bottom));
             display: flex; flex-direction: column; gap: 6px; }
  .side-logo { display: flex; align-items: center; gap: 10px; padding: 0 8px 18px; }
  .logo { width: 34px; height: 34px; border-radius: 9px; background: #fff; box-shadow: 0 1px 4px rgba(0,0,0,.12);
          display: flex; align-items: center; justify-content: center; overflow: hidden; flex: none; }
  .side-brand { font-weight: 700; font-size: 18px; }
  .nav-item { display: flex; align-items: center; gap: 12px; padding: 11px 14px; border-radius: 8px;
              font-size: 14px; font-weight: 500; color: var(--ink); cursor: pointer; text-decoration: none; }
  .nav-item.active { color: var(--blue-d); background: var(--blue-soft); }
  .nav-dot { width: 8px; height: 8px; border-radius: 2px; background: var(--faint); }
  .nav-item.active .nav-dot { background: var(--blue); }
  .nav-badge { margin-left: auto; background: var(--red); color: #fff; font-size: 11px; font-weight: 700;
               min-width: 18px; height: 18px; border-radius: 9px; display: none; align-items: center; justify-content: center; padding: 0 5px; }
  .devices { margin-top: auto; padding: 14px; background: #fff; border-radius: 12px; border: 1px solid var(--line); }
  .dev-title { font-size: 11px; letter-spacing: .8px; color: var(--muted); font-weight: 500; margin-bottom: 10px; }
  .dev-row { display: flex; align-items: center; gap: 8px; padding: 5px 0; font-size: 13px; }
  .dev-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--green); }
  .dev-status { margin-left: auto; font-size: 11px; color: var(--muted); }

  /* main */
  .main { flex: 1; display: flex; flex-direction: column; min-width: 0; max-width: 1160px; margin: 0 auto; width: 100%; }
  .topbar { height: 60px; border-bottom: 1px solid var(--line); background: rgba(255,255,255,.7);
            backdrop-filter: blur(6px); display: flex; align-items: center; padding: 0 22px; gap: 14px;
            position: sticky; top: 0; z-index: 10; padding-top: env(safe-area-inset-top); }
  .topbar-title { font-size: 20px; font-weight: 700; }
  .topbar-pill { font-size: 13px; color: var(--muted); background: var(--grey-soft); padding: 4px 10px; border-radius: 12px; white-space: nowrap; }
  .topbar-right { margin-left: auto; display: flex; align-items: center; gap: 14px; }
  .bell { position: relative; width: 36px; height: 36px; border-radius: 50%; background: var(--grey-soft);
          display: flex; align-items: center; justify-content: center; font-size: 15px; }
  .bell.has::after { content: ''; position: absolute; top: 6px; right: 7px; width: 9px; height: 9px;
                     border-radius: 50%; background: var(--red); border: 2px solid #fff; }
  .avatar-me { width: 36px; height: 36px; border-radius: 50%; background: var(--blue-d); color: #fff;
               display: flex; align-items: center; justify-content: center; font-size: 13px; font-weight: 700; }

  .cols { flex: 1; display: flex; gap: 20px; padding: 22px; min-height: 0; align-items: flex-start; }
  .col-main { flex: 1.4; display: flex; flex-direction: column; gap: 20px; min-width: 0; }
  .col-side { flex: 1; min-width: 0; }
  /* empty approval/usage containers must not create phantom flex gaps that
     push the fleet card out of line with the activity card */
  #approvals:empty, #usage:empty { display: none; }

  /* expressive Pac mascot — avatar / loading / idle / success / empty (PacmanMascot.dc.html) */
  .mascot { position: relative; display: inline-flex; align-items: center; justify-content: center; }
  .mascot .mbox { position: relative; width: 80%; height: 80%; display: flex; align-items: center; justify-content: center; }
  .mascot .mbody { position: relative; width: 78%; height: 78%; transform-origin: center bottom; }
  .mascot.avatar  .mbody { animation: pm-bob 1.8s ease-in-out infinite; }
  .mascot.loading .mbody { animation: pm-bob 0.8s ease-in-out infinite; }
  .mascot.idle    .mbody { animation: pm-chase 3s ease-in-out infinite; }
  .mascot.success .mbody { animation: pm-jump 0.7s ease-in-out infinite; }
  .mascot.empty   .mbody { animation: pm-bob 2.2s ease-in-out infinite; }
  .mascot .mpac { position: absolute; inset: 0; width: 100%; height: 100%; filter: drop-shadow(0 2px 0 rgba(0,0,0,.12)); animation: pm-chomp .42s steps(2, jump-none) infinite; }
  .mascot .meye { position: absolute; left: 52%; top: 20%; width: 8%; height: 8%; background: #202124; border-radius: 1px; }
  .mascot .marm { position: absolute; bottom: 8%; width: 24%; height: 20%; }
  .mascot .marm.ml { left: -16%; transform-origin: right center; animation: pm-armL .8s ease-in-out infinite; }
  .mascot .marm.mr { right: -16%; transform-origin: left center; animation: pm-armR .8s ease-in-out infinite; }
  .mascot .marm .stick { position: absolute; top: 33%; width: 70%; height: 34%; background: #FDD835; border-radius: 2px; }
  .mascot .marm.ml .stick { left: 0; }  .mascot .marm.mr .stick { right: 0; }
  .mascot .marm .glove { position: absolute; top: 18%; width: 44%; height: 64%; background: #fff; border: 2px solid #202124; box-sizing: border-box; border-radius: 3px; }
  .mascot .marm.ml .glove { left: -8%; }  .mascot .marm.mr .glove { right: -8%; }
  .mascot .mghost { position: absolute; right: -2%; top: 16%; width: 34%; height: 40%; animation: pm-ghostrun 3s ease-in-out infinite; }
  .mascot .mghost .g { position: absolute; inset: 0; animation: pm-ghost .9s ease-in-out infinite; }
  .mascot .mghost .body { position: absolute; inset: 0; background: #4FC3F7; border-radius: 46% 46% 0 0; clip-path: polygon(0 0,100% 0,100% 78%,86% 100%,72% 82%,58% 100%,44% 82%,30% 100%,16% 82%,0 100%); }
  .mascot .mghost .ge { position: absolute; top: 30%; width: 20%; height: 26%; background: #fff; border-radius: 50%; }
  .mascot .mghost .ge.l { left: 20%; }  .mascot .mghost .ge.r { right: 20%; }
  .mascot .mghost .gp { position: absolute; top: 38%; width: 9%; height: 12%; background: #202124; }
  .mascot .mghost .gp.l { left: 24%; }  .mascot .mghost .gp.r { right: 24%; }
  .mascot .mlap { position: absolute; left: 14%; bottom: -6%; width: 72%; height: 44%; }
  .mascot .mlap .scr { position: absolute; bottom: 22%; left: 6%; width: 88%; height: 60%; background: #5f6368; border: 2px solid #202124; border-radius: 2px; box-sizing: border-box; }
  .mascot .mlap .lit { position: absolute; bottom: 24%; left: 10%; width: 80%; height: 52%; background: #174ea6; border-radius: 1px; }
  .mascot .mlap .base { position: absolute; bottom: 0; left: 0; width: 100%; height: 24%; background: #9aa0a6; border: 2px solid #202124; border-radius: 2px 2px 3px 3px; box-sizing: border-box; }
  .mascot .spark { position: absolute; animation: pm-spark 1.1s ease-in-out infinite; }
  .mascot .zzz { position: absolute; font-family: var(--mono); color: #9aa0a6; animation: pm-zzz 2.4s ease-in-out infinite; }
  @keyframes pm-chomp { 0%,100% { clip-path: polygon(0 0,100% 0,54% 50%,100% 100%,0 100%); } 50% { clip-path: polygon(0 0,100% 0,100% 50%,100% 100%,0 100%); } }
  @keyframes pm-bob { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-7%); } }
  @keyframes pm-jump { 0%,100% { transform: translateY(0) scale(1,1); } 30% { transform: translateY(-22%) scale(.94,1.06); } 60% { transform: translateY(0) scale(1.05,.95); } }
  @keyframes pm-chase { 0% { transform: translateX(-8%); } 50% { transform: translateX(8%); } 100% { transform: translateX(-8%); } }
  @keyframes pm-ghost { 0% { transform: translate(0,0); } 50% { transform: translate(0,-12%); } 100% { transform: translate(0,0); } }
  @keyframes pm-ghostrun { 0% { transform: translateX(18%); } 50% { transform: translateX(38%); } 100% { transform: translateX(18%); } }
  @keyframes pm-spark { 0%,100% { transform: scale(.4); opacity: 0; } 50% { transform: scale(1); opacity: 1; } }
  @keyframes pm-zzz { 0% { transform: translate(0,0); opacity: 0; } 20% { opacity: 1; } 100% { transform: translate(120%,-140%); opacity: 0; } }
  @keyframes pm-armL { 0%,100% { transform: rotate(-8deg); } 50% { transform: rotate(6deg); } }
  @keyframes pm-armR { 0%,100% { transform: rotate(8deg); } 50% { transform: rotate(-6deg); } }
  @media (prefers-reduced-motion: reduce) { .mascot, .mascot * { animation: none !important; } }

  /* "All clear" state (mirrors the watch idle face) */
  .allclear { background: #fff; border: 1px solid var(--line); border-radius: 24px; padding: 26px;
              display: flex; flex-direction: column; align-items: center; gap: 6px; box-shadow: 0 4px 14px rgba(0,0,0,.05); }
  .allclear .ac-t { font-size: 20px; font-weight: 700; color: var(--blue); }
  .allclear .ac-s { font-size: 13px; color: var(--muted); }

  /* panels */
  .panel { background: #fff; border: 1px solid var(--line); border-radius: 24px; overflow: hidden; }
  .phead { display: flex; align-items: center; gap: 8px; padding: 16px 20px; font-size: 15px; font-weight: 700; border-bottom: 1px solid var(--line); }
  .live-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); animation: blink 1.4s infinite; }
  @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: .25; } }

  /* hero approval */
  .hero { background: #fff; border: 2px solid var(--red); border-radius: 24px; padding: 22px; box-shadow: 0 6px 20px rgba(234,67,53,.12); }
  .hero + .hero { margin-top: 16px; }
  .hhead { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 16px; }
  .risk { font-family: var(--mono); font-size: 11px; font-weight: 500; letter-spacing: .6px; padding: 5px 10px; border-radius: 6px; }
  .hagent { font-size: 14px; font-weight: 500; }
  .hwant { font-size: 13px; color: var(--muted); }
  .hexp { margin-left: auto; font-family: var(--mono); font-size: 13px; color: var(--red-d); display: flex; align-items: center; gap: 8px; }
  .blink { width: 8px; height: 8px; border-radius: 50%; background: var(--red); animation: blink 1s infinite; }
  .hlabel { font-size: 14px; color: var(--muted); margin-bottom: 6px; }
  .htask { font-size: 16px; font-weight: 500; margin-bottom: 16px; }
  .hcmd { background: #202124; border-radius: 12px; padding: 15px 18px; font-family: var(--mono); font-size: 14px;
          color: #f1f3f4; margin-bottom: 14px; word-break: break-all; }
  .hcmd .d { color: #5f6368; }
  .hwarn { display: flex; gap: 8px; font-size: 13px; color: var(--red-d); background: #fef7f6; padding: 10px 14px; border-radius: 8px; margin-bottom: 18px; }
  .buttons { display: flex; gap: 12px; }
  .buttons button { height: 48px; border: none; border-radius: 24px; font-family: inherit; font-size: 15px; font-weight: 500; cursor: pointer; }
  .buttons .deny { flex: 1; background: var(--red); color: #fff; }
  .buttons .allow { flex: 2; background: var(--blue); color: #fff; }
  .buttons button:disabled { opacity: .5; }

  /* agent fleet (design style: dot · name · task · pill) */
  .fleet-row { display: flex; align-items: center; gap: 14px; padding: 14px 20px; border-bottom: 1px solid var(--grey-soft); cursor: pointer; }
  .fleet-row:last-child { border-bottom: none; }
  .fleet-row:hover { background: #fafbfc; }
  .fdot2 { width: 9px; height: 9px; border-radius: 50%; flex: none; }
  .fname { min-width: 130px; font-size: 14px; font-weight: 500; font-family: var(--mono); }
  .ftask2 { flex: 1; font-size: 13px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .fpill { font-size: 12px; font-weight: 500; padding: 4px 10px; border-radius: 12px; white-space: nowrap; }
  .fkbd { color: var(--faint); font-size: 14px; flex: none; }
  .fleet-empty { padding: 40px 20px; text-align: center; color: var(--muted); font-size: 14px;
                 display: flex; flex-direction: column; align-items: center; gap: 12px; }
  .fleet-empty .dim { color: var(--faint); font-size: 13px; }

  /* live activity feed */
  .feed-row { display: flex; gap: 12px; padding: 11px 20px; }
  .ftime { font-family: var(--mono); font-size: 12px; color: var(--faint); min-width: 42px; }
  .fdot { width: 7px; height: 7px; border-radius: 50%; margin-top: 6px; flex: none; }
  .ftext { font-size: 13px; line-height: 1.4; }
  .ftext b { font-family: var(--mono); font-weight: 500; }
  .ftext span { color: var(--muted); }
  .feed-empty { padding: 22px 20px; text-align: center; color: var(--faint); font-size: 13px; }

  /* usage card */
  .ucard { background: #fff; border: 1px solid var(--line); border-radius: 24px; padding: 16px 20px; }
  .uhead { display: flex; justify-content: space-between; align-items: center; font-size: 13px; color: var(--muted); }
  .uhead b { font-family: var(--mono); font-size: 14px; }
  .ubar { height: 7px; background: var(--grey-soft); border-radius: 4px; margin: 9px 0; overflow: hidden; }
  .ubar i { display: block; height: 100%; border-radius: 4px; }
  .uspark { display: flex; align-items: flex-end; gap: 3px; height: 26px; }
  .uspark span { flex: 1; border-radius: 2px; opacity: .8; }

  /* terminal overlay */
  #terminal { position: fixed; left: 0; right: 0; bottom: 0; z-index: 40; background: #fff; border-radius: 20px 20px 0 0;
              box-shadow: 0 -12px 40px rgba(0,0,0,.25); transform: translateY(105%); transition: transform .25s;
              padding: 12px 14px calc(14px + env(safe-area-inset-bottom)); max-height: 82vh; display: flex; flex-direction: column;
              max-width: 720px; margin: 0 auto; }
  #terminal.open { transform: translateY(0); }
  .thead { display: flex; align-items: center; margin-bottom: 10px; }
  .tname { font-family: var(--mono); font-size: 14px; font-weight: 500; }
  .tclose { margin-left: auto; border: 1px solid var(--line); background: #fff; border-radius: var(--pill); padding: 6px 14px; font-size: 12px; color: var(--muted); cursor: pointer; }
  .term { flex: 1; background: #202124; color: #f1f3f4; border-radius: 12px; padding: 12px; font-family: var(--mono);
          font-size: 12px; line-height: 1.4; white-space: pre-wrap; overflow: auto; min-height: 180px; }
  .keys { display: flex; flex-wrap: wrap; gap: 7px; margin: 10px 0; }
  .keys button { border: 1px solid var(--line); background: #fff; border-radius: 9px; padding: 8px 12px; font-size: 13px; font-family: var(--mono); cursor: pointer; color: var(--ink); }
  .keys .y { background: var(--green-soft); border-color: transparent; color: #1e7e34; }
  .keys .n { background: var(--red-soft); border-color: transparent; color: var(--red-d); }
  .tinput { display: flex; gap: 8px; }
  .tinput input { flex: 1; height: 40px; border: 1px solid var(--line); border-radius: var(--pill); padding: 0 14px; font-family: var(--mono); font-size: 13px; outline: none; }
  .tinput button { width: 40px; height: 40px; border: none; border-radius: 50%; background: var(--blue); color: #fff; font-size: 15px; cursor: pointer; }

  /* footer */
  #foot { position: fixed; left: 0; right: 0; bottom: 0; z-index: 20; display: flex; align-items: center; justify-content: center; gap: 8px;
          padding: 8px 0 calc(8px + env(safe-area-inset-bottom)); background: rgba(232,234,237,.9); backdrop-filter: blur(8px); font-size: 12px; color: var(--muted); }
  #foot .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); }
  #foot.offline .dot { background: var(--red); }

  /* responsive — phone */
  @media (max-width: 860px) {
    .app { flex-direction: column; }
    .sidebar { width: 100%; flex-direction: row; align-items: center; gap: 8px; overflow-x: auto;
               padding: max(10px, env(safe-area-inset-top)) 12px 10px; border-right: none; border-bottom: 1px solid var(--line); }
    .side-logo { padding: 0 6px 0 0; }
    .nav-item { padding: 8px 12px; white-space: nowrap; }
    .devices { display: none; }
    .cols { flex-direction: column; padding: 14px; gap: 16px; }
    .col-side { position: static; width: 100%; }
    .col-main { width: 100%; }
    .topbar { padding-left: 16px; padding-right: 16px; }
  }
</style>
</head>
<body>
<div class="app">
  <main class="main">
    <div class="topbar">
      <div class="logo" id="logo"></div>
      <div class="topbar-title">AgentGarden</div>
      <div class="topbar-pill" id="topPill"></div>
    </div>
    <div class="cols">
      <div class="col-main">
        <div id="approvals"></div>
        <section class="panel">
          <div class="phead">Agent fleet</div>
          <div id="list"></div>
        </section>
        <div id="usage"></div>
      </div>
      <div class="col-side">
        <section class="panel">
          <div class="phead"><span class="live-dot"></span> Live activity</div>
          <div id="feed"></div>
        </section>
      </div>
    </div>
  </main>
</div>

<div id="terminal"></div>
<footer id="foot"><span class="dot"></span><span id="foottext"></span></footer>

<script>
const foot = document.getElementById('foot');
const footText = document.getElementById('foottext');
const TOKEN = new URLSearchParams(location.search).get('token') || '';
const AUTH = { 'Authorization': 'Bearer ' + TOKEN };
function auth(extra) { return Object.assign({}, AUTH, extra || {}); }
let openTerm = null;
let feedLog = [];

function esc(s) { return String(s).replace(/[&<>"']/g, c => '&#' + c.charCodeAt(0) + ';'); }
function nowHM() { const d = new Date(); return String(d.getHours()).padStart(2,'0') + ':' + String(d.getMinutes()).padStart(2,'0'); }

// Expressive pixel-art Pac mascot — 20x20 grid + arms/gloves + eye + chomp, with
// a per-mode companion: idle→ghost, loading→laptop, success→sparkles, empty→zzz
// (a faithful port of PacmanMascot.dc.html's five modes).
function mascotSVG(mode, px) {
  mode = mode || 'avatar';
  const N = 20, c = (N - 1) / 2, r = N / 2 - 0.2, cell = 100 / N, cs = +(cell + 0.4).toFixed(2);
  const BASE = '#FDD835', HI = '#FFEE58', SH = '#F9A825', OUT = '#3a2f00';
  let rects = '';
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const d = Math.hypot(x - c, y - c); if (d > r) continue;
    let col = BASE;
    if (d > r - 1.15) col = OUT;
    else if ((x - c) + (y - c) < -3.2) col = HI;
    else if ((x - c) + (y - c) > 4) col = SH;
    rects += `<rect x="${(x*cell).toFixed(2)}" y="${(y*cell).toFixed(2)}" width="${cs}" height="${cs}" fill="${col}"/>`;
  }
  const ghost = mode === 'idle' ? '<span class="mghost"><span class="g">'
    + '<span class="body"></span><span class="ge l"></span><span class="ge r"></span>'
    + '<span class="gp l"></span><span class="gp r"></span></span></span>' : '';
  const lap = mode === 'loading' ? '<span class="mlap"><span class="scr"></span><span class="lit"></span><span class="base"></span></span>' : '';
  const spark = mode === 'success'
    ? `<span class="spark" style="left:-8%;top:-6%;color:#FBBC04;font-size:${(px*0.16)|0}px">✦</span>`
    + `<span class="spark" style="right:-6%;top:6%;color:#1a73e8;font-size:${(px*0.12)|0}px;animation-delay:.3s">✦</span>`
    + `<span class="spark" style="right:8%;top:-12%;color:#34a853;font-size:${(px*0.1)|0}px;animation-delay:.6s">✦</span>` : '';
  const zzz = mode === 'empty'
    ? `<span class="zzz" style="right:-4%;top:-6%;font-size:${(px*0.16)|0}px">z</span>`
    + `<span class="zzz" style="right:2%;top:2%;font-size:${(px*0.12)|0}px;animation-delay:.8s">z</span>` : '';
  return `<span class="mascot ${mode}" style="width:${px}px;height:${px}px"><span class="mbox">${ghost}`
    + '<span class="mbody"><span class="marm ml"><i class="stick"></i><i class="glove"></i></span>'
    + '<span class="marm mr"><i class="stick"></i><i class="glove"></i></span>'
    + `<svg class="mpac" viewBox="0 0 100 100" shape-rendering="crispEdges">${rects}</svg><i class="meye"></i>`
    + `${lap}${spark}${zzz}</span></span></span>`;
}

function riskOf(a) {
  const d = ((a.detail || '') + ' ' + (a.tool || '')).toLowerCase();
  if (/(-rf|--force|\bforce\b|\brm\b|sudo|push|drop\b|delete|reset --hard|mkfs|:>|truncate)/.test(d))
    return { lvl: 'HIGH', col: 'var(--red-d)', bg: 'var(--red-soft)' };
  if (/(edit|write|multiedit|notebookedit|create)/.test(d))
    return { lvl: 'MED', col: 'var(--amber)', bg: 'var(--amber-soft)' };
  return { lvl: 'LOW', col: 'var(--blue-d)', bg: 'var(--blue-soft)' };
}
function expiryText(iso) {
  const end = Date.parse(iso) + 280000;
  let s = Math.max(0, Math.round((end - Date.now()) / 1000));
  return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
}

function fleetState(a) {
  if (a.isError) return { col: '#ea4335', halo: 'var(--red-soft)', label: 'error' };
  if (a.needsAttention) return { col: '#ea4335', halo: 'var(--red-soft)', label: 'blocked' };
  if (a.isDone) return { col: '#9aa0a6', halo: 'var(--grey-soft)', label: 'done' };
  return { col: '#34a853', halo: 'var(--green-soft)', label: 'running' };
}
function render(agents) {
  const el = document.getElementById('list');
  if (!agents.length) {
    el.innerHTML = '<div class="fleet-empty">' + mascotSVG('empty', 64) + 'Belum ada agen jalan.'
      + '<span class="dim">Mulai sesi Claude Code di Mac.</span></div>';
    return;
  }
  el.innerHTML = agents.map(a => {
    const s = fleetState(a);
    return `<div class="fleet-row" onclick="openTerminal('${esc(a.id)}')">
      <span class="fdot2" style="background:${s.col};box-shadow:0 0 0 4px ${s.halo}"></span>
      <div class="fname">${esc(a.id)}</div>
      <div class="ftask2">${esc(a.task || a.lastTool || '—')}</div>
      <span class="fpill" style="color:${s.col};background:${s.halo}">${s.label}</span>
      <span class="fkbd">⌨</span>
    </div>`; }).join('');
}

function renderApprovals(items) {
  const box = document.getElementById('approvals');
  if (!items.length) {
    const n = (window.lastAgents || []).length;
    box.innerHTML = n ? '<div class="allclear">' + mascotSVG('idle', 96)
      + '<div class="ac-t">All clear</div><div class="ac-s">' + n + ' agents running · 0 waiting</div></div>' : '';
    return;
  }
  const tasks = {}; (window.lastAgents || []).forEach(a => tasks[a.id] = a.task);
  box.innerHTML = items.map(a => {
    const r = riskOf(a), task = tasks[a.agent];
    return `<div class="hero" style="border-color:${r.col}">
      <div class="hhead">
        <span class="risk" style="color:${r.col};background:${r.bg}">● ${r.lvl} RISK</span>
        <span class="hagent">${esc(a.agent)}</span>
        <span class="hwant">wants to run ${esc(a.tool)}</span>
        <div class="hexp"><span class="blink"></span>expires ${expiryText(a.createdAt)}</div>
      </div>
      ${task ? `<div class="hlabel">Task</div><div class="htask">${esc(task)}</div>` : ''}
      <div class="hcmd"><span class="d">$</span> ${esc(a.detail)}</div>
      ${r.lvl === 'HIGH' ? `<div class="hwarn">⚠️ Aksi berisiko — cek dulu sebelum approve, bisa nggak bisa di-undo.</div>` : ''}
      <div class="buttons">
        <button class="deny" onclick="decide('${a.id}','deny',this)">Deny</button>
        <button class="allow" onclick="decide('${a.id}','allow',this)">Approve &amp; run</button>
      </div>
    </div>`; }).join('');
}

function pushFeed(agent, msg, col) { feedLog.unshift({ time: nowHM(), agent, msg, color: col }); if (feedLog.length > 16) feedLog.pop(); }
function renderFeed() {
  const el = document.getElementById('feed');
  if (!feedLog.length) { el.innerHTML = '<div class="feed-empty">Belum ada aktivitas.</div>'; return; }
  el.innerHTML = feedLog.map(f => `<div class="feed-row"><span class="ftime">${f.time}</span>`
    + `<span class="fdot" style="background:${f.color}"></span>`
    + `<div class="ftext"><b>${esc(f.agent)}</b> <span>${esc(f.msg)}</span></div></div>`).join('');
}
function logActivity(agents) {
  const prev = window._prevA || {}, cur = {};
  agents.forEach(a => {
    cur[a.id] = { att: !!a.needsAttention, done: !!a.isDone, err: !!a.isError, tool: a.lastTool || '' };
    const p = prev[a.id];
    if (!p) pushFeed(a.id, 'muncul di fleet', '#1a73e8');
    else if (cur[a.id].err && !p.err) pushFeed(a.id, 'error', '#ea4335');
    else if (cur[a.id].att && !p.att) pushFeed(a.id, 'minta approval', '#ea4335');
    else if (cur[a.id].done && !p.done) pushFeed(a.id, 'selesai', '#9aa0a6');
    else if (cur[a.id].tool && cur[a.id].tool !== p.tool) pushFeed(a.id, '· ' + cur[a.id].tool, '#34a853');
  });
  window._prevA = cur; renderFeed();
}

function updateCounts(agents, approvals) {
  const p = approvals.length, m = agents.length;
  document.getElementById('topPill').textContent = p + ' pending · ' + m + ' agents live';
}

function renderUsage(u) {
  const el = document.getElementById('usage');
  if (!u || u.today == null) { el.innerHTML = ''; return; }
  const pct = Math.min(u.pct, 1);
  const col = u.pct >= 1 ? '#ea4335' : (u.pct >= 0.8 ? '#f9a825' : '#34a853');
  const days = u.days || [];
  const mx = Math.max.apply(null, days.map(d => d.cost).concat(0.0001));
  const bars = days.map(d => `<span style="height:${Math.max(3, 26 * d.cost / mx)}px;background:${col}"></span>`).join('');
  el.innerHTML = `<div class="ucard">
     <div class="uhead"><span>Model spend hari ini</span><b style="color:${col}">$${u.today.toFixed(2)} / $${u.budget.toFixed(0)}</b></div>
     <div class="ubar"><i style="width:${(pct*100).toFixed(0)}%;background:${col}"></i></div>
     <div class="uspark">${bars}</div></div>`;
}

async function decide(id, decision, btn) {
  btn.closest('.buttons').querySelectorAll('button').forEach(b => b.disabled = true);
  try { await fetch('/approval/' + id + '/decide', { method: 'POST', headers: auth({ 'Content-Type': 'application/json' }), body: JSON.stringify({ decision }) }); } catch {}
  tick();
}
async function send(agent, text) {
  if (!text) return;
  try { await fetch('/prompt', { method: 'POST', headers: auth({ 'Content-Type': 'application/json' }), body: JSON.stringify({ agent, text }) }); } catch {}
}

// live terminal (tmux bridge)
function openTerminal(id) {
  openTerm = id;
  const t = document.getElementById('terminal');
  t.innerHTML = `
    <div class="thead"><span class="tname">⌨ ${esc(id)}</span><button class="tclose" onclick="closeTerminal()">tutup ✕</button></div>
    <pre class="term" id="termscreen">memuat…</pre>
    <div class="keys">
      <button class="y" onclick="sendKeys(['1','Enter'])">1·Yes</button>
      <button class="n" onclick="sendKeys(['2','Enter'])">2·No</button>
      <button onclick="sendKeys(['3','Enter'])">3</button>
      <button onclick="sendKeys(['y'])">y</button><button onclick="sendKeys(['n'])">n</button>
      <button onclick="sendKeys(['Up'])">↑</button><button onclick="sendKeys(['Down'])">↓</button>
      <button onclick="sendKeys(['Enter'])">⏎</button><button onclick="sendKeys(['Escape'])">esc</button>
    </div>
    <div class="tinput"><input id="tin" enterkeyhint="send" placeholder="ketik ke terminal…" onkeydown="if(event.key==='Enter')sendText()"><button onclick="sendText()">➤</button></div>`;
  t.classList.add('open');
  refreshTerminal();
}
function closeTerminal() { openTerm = null; document.getElementById('terminal').classList.remove('open'); }
async function refreshTerminal() {
  if (!openTerm) return;
  try {
    const r = await fetch('/terminal/' + encodeURIComponent(openTerm), { headers: AUTH });
    const j = await r.json();
    const pre = document.getElementById('termscreen');
    if (pre) { const b = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 24;
      pre.textContent = j.screen || '(terminal kosong — jalanin sesi via garden-claude.sh)'; if (b) pre.scrollTop = pre.scrollHeight; }
  } catch {}
}
async function sendKeys(keys) {
  if (!openTerm) return;
  try { await fetch('/keys', { method: 'POST', headers: auth({ 'Content-Type': 'application/json' }), body: JSON.stringify({ agent: openTerm, keys }) }); } catch {}
  setTimeout(refreshTerminal, 250);
}
function sendText() { const i = document.getElementById('tin'); if (!i || !i.value) return; const t = i.value; i.value = ''; sendKeys([t, 'Enter']); }

function online() { foot.classList.remove('offline'); footText.textContent = 'AgentGarden · live'; }
function offline(t) { foot.classList.add('offline'); footText.textContent = t; }
async function tick() {
  try {
    const [ra, rp, ru] = await Promise.all([
      fetch('/agents', { headers: AUTH }), fetch('/approvals', { headers: AUTH }), fetch('/usage', { headers: AUTH })]);
    if (ra.status === 401 || rp.status === 401) { offline('token salah/hilang — buka ulang link dari app'); return; }
    const agents = await ra.json(), approvals = await rp.json();
    window.lastAgents = agents;
    logActivity(agents);
    render(agents); renderApprovals(approvals); updateCounts(agents, approvals);
    try { renderUsage(await ru.json()); } catch {}
    if (openTerm) refreshTerminal();
    online();
  } catch { offline('koneksi ke Mac putus — cek Tailscale'); }
}
document.getElementById('logo').innerHTML = mascotSVG('avatar', 30);
tick();
setInterval(tick, 1500);
</script>
</body>
</html>
"""#
}
