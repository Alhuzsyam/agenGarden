import Foundation

/// Mobile web dashboard served at GET / — open from the phone over Tailscale,
/// "Add to Home Screen" makes it a PWA. Visual language follows the Minimals
/// ("E") design tokens: Public Sans, green primary #00A76F, #f4f6f8 canvas.
enum DashboardPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#161c24">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>AgentGarden</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Public+Sans:wght@400;500;600;700;800&display=swap');

  :root {
    /* Type */
    --font: "Public Sans", -apple-system, system-ui, "Segoe UI", Roboto,
            "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji";
    --fs-xs: 13.33px; --fs-sm: 14px; --fs-md: 16px;
    --fs-lg: 18px; --fs-xl: 19px; --fs-2xl: 24px;
    /* Color */
    --primary: #00a76f; --primary-dark: #5be49b; --primary-light: #5be49b;
    --primary-soft: rgba(0, 167, 111, .16);
    --text: #ffffff; --text-2: #919eab;
    --bg: #161c24; --card: #212b36; --border: rgba(145,158,171,.16);
    --amber: #ffab00; --amber-soft: rgba(255, 171, 0, .16);
    --red: #ff5630; --red-soft: rgba(255, 86, 48, .16);
    /* Space */
    --s1: 4px; --s2: 6px; --s3: 8px; --s4: 12px; --s5: 16px; --s6: 24px;
    /* Radius / motion */
    --r-card: 16px; --r-ctl: 8px; --r-pill: 50px;
    --shadow-card: 0 0 2px rgba(0,0,0,.24), 0 12px 24px -8px rgba(0,0,0,.5);
    --dur-fast: 150ms; --dur: 250ms;
  }

  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text);
    font-family: var(--font); font-size: var(--fs-md); line-height: 24px;
    font-weight: 400; -webkit-font-smoothing: antialiased;
    padding: max(var(--s5), env(safe-area-inset-top)) var(--s5) 40px;
    min-height: 100vh;
  }

  /* ---- Header ---- */
  header {
    display: flex; align-items: center; gap: var(--s4);
    padding: var(--s3) var(--s1) var(--s6);
  }
  .logo {
    width: 36px; height: 36px; flex: none; border-radius: 10px;
    background: linear-gradient(135deg, var(--primary-light), var(--primary));
    display: grid; place-items: center; color: #fff; font-size: 18px;
    box-shadow: 0 4px 10px -2px rgba(0,167,111,.5);
  }
  header h1 {
    font-size: var(--fs-lg); font-weight: 700; letter-spacing: -.2px;
  }
  header .sub { font-size: var(--fs-xs); color: var(--text-2); font-weight: 400; }
  header .count {
    margin-left: auto; font-size: var(--fs-xs); font-weight: 600;
    color: var(--primary-dark); background: var(--primary-soft);
    padding: var(--s2) var(--s4); border-radius: var(--r-pill);
  }

  /* ---- Agent card ---- */
  .plot { margin-bottom: var(--s4); }
  .card {
    background: var(--card); border: 1px solid var(--border);
    border-radius: var(--r-card); box-shadow: var(--shadow-card);
    padding: var(--s5); display: flex; align-items: center; gap: var(--s4);
    transition: border-color var(--dur), box-shadow var(--dur);
  }
  .avatar {
    position: relative; width: 48px; height: 48px; flex: none; border-radius: 50%;
    background: var(--primary-soft); overflow: visible;
  }
  .avatar img {
    width: 48px; height: 48px; border-radius: 50%; object-fit: cover;
    display: block;
  }
  .avatar .fallback {
    width: 48px; height: 48px; border-radius: 50%;
    display: none; align-items: center; justify-content: center;
    font-size: var(--fs-lg); font-weight: 700; color: var(--primary-dark);
    background: var(--primary-soft);
  }
  .badge {
    position: absolute; right: -1px; bottom: -1px;
    width: 14px; height: 14px; border-radius: 50%; border: 2.5px solid var(--card);
  }
  .badge.run  { background: var(--primary); }
  .badge.attn { background: var(--amber); }
  .badge.done { background: var(--primary); }
  .badge.err  { background: var(--red); }
  .badge.run::after {
    content: ""; position: absolute; inset: -3px; border-radius: 50%;
    border: 2px solid var(--primary); opacity: .5; animation: ping 1.6s ease-out infinite;
  }
  @keyframes ping { 0% { transform: scale(.8); opacity: .6 } 100% { transform: scale(1.7); opacity: 0 } }

  .info { min-width: 0; flex: 1; }
  .name {
    font-size: var(--fs-md); font-weight: 600; color: var(--text);
    letter-spacing: -.2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .task {
    font-size: var(--fs-xs); color: var(--text-2); margin-top: 2px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .state {
    display: inline-flex; align-items: center; gap: 5px; margin-top: var(--s3);
    font-size: var(--fs-xs); font-weight: 600; color: var(--primary-dark);
    background: var(--primary-soft); padding: 3px var(--s3); border-radius: var(--r-pill);
  }
  .state .tool { color: var(--text-2); font-weight: 500; }
  .card.attention { border-color: var(--amber); }
  .card.attention .state { color: var(--amber); background: var(--amber-soft); }
  .card.error .state { color: #ffac9b; background: var(--red-soft); }

  .meta {
    display: flex; flex-direction: column; align-items: flex-end; gap: var(--s3);
    flex: none;
  }
  .meta .age { font-size: var(--fs-xs); color: var(--text-2); font-weight: 500; }
  .tbtn {
    width: 38px; height: 38px; border-radius: var(--r-ctl);
    background: var(--primary-soft); color: var(--primary-dark);
    border: none; font-size: 17px; cursor: pointer;
    transition: background var(--dur-fast), transform var(--dur-fast);
  }
  .tbtn:hover { background: rgba(0,167,111,.16); }
  .tbtn:active { transform: scale(.94); }

  /* ---- Compose ---- */
  .compose { display: flex; gap: var(--s3); margin-top: var(--s3); padding: 0 var(--s1); }
  .compose input, .tinput input {
    flex: 1; min-width: 0; background: var(--card); border: 1px solid var(--border);
    border-radius: var(--r-ctl); color: var(--text); padding: 11px var(--s4);
    font-family: inherit; font-size: var(--fs-sm);
    transition: border-color var(--dur-fast), box-shadow var(--dur-fast);
  }
  .compose input::placeholder { color: #919eab; }
  .compose input:focus, .tinput input:focus {
    outline: none; border-color: var(--primary);
    box-shadow: 0 0 0 3px var(--primary-soft);
  }
  .compose button, .tinput button {
    flex: none; min-width: 46px; background: var(--primary); color: #fff; border: none;
    border-radius: var(--r-ctl); padding: 0 var(--s5); font-size: var(--fs-md);
    font-weight: 700; cursor: pointer;
    transition: background var(--dur-fast), transform var(--dur-fast);
  }
  .compose button:hover, .tinput button:hover { background: var(--primary-dark); }
  .compose button:active, .tinput button:active { transform: scale(.96); }
  .compose button:disabled { opacity: .4; cursor: default; }

  /* ---- Approvals ---- */
  #approvals { margin-bottom: var(--s5); display: flex; flex-direction: column; gap: var(--s4); }
  .approval {
    background: var(--card); border: 1px solid var(--amber);
    border-left: 4px solid var(--amber);
    border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: var(--s5);
  }
  .approval .who { font-size: var(--fs-sm); color: var(--text); margin-bottom: var(--s3); }
  .approval .who b { color: var(--amber); }
  .approval .cmd {
    background: var(--bg); border: 1px solid var(--border); border-radius: var(--r-ctl);
    padding: var(--s4); font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: var(--fs-xs); color: var(--text); word-break: break-all;
    margin-bottom: var(--s4); max-height: 140px; overflow-y: auto;
  }
  .approval .buttons { display: flex; gap: var(--s4); }
  .approval button {
    flex: 1; padding: 13px 0; border: none; border-radius: var(--r-ctl);
    font-family: inherit; font-size: var(--fs-sm); font-weight: 700; cursor: pointer;
    transition: filter var(--dur-fast), transform var(--dur-fast);
  }
  .approval button:active { transform: scale(.97); }
  .approval .allow { background: var(--primary); color: #fff; }
  .approval .deny { background: var(--red); color: #fff; }
  .approval button:hover { filter: brightness(.94); }
  .approval button:disabled { opacity: .4; cursor: default; }

  /* ---- Empty / footer ---- */
  .empty {
    text-align: center; padding: 72px 24px; color: var(--text-2); font-size: var(--fs-sm);
  }
  .empty .ico {
    width: 64px; height: 64px; margin: 0 auto var(--s5); border-radius: 20px;
    background: var(--primary-soft); display: grid; place-items: center; font-size: 30px;
  }
  footer {
    text-align: center; font-size: var(--fs-xs); color: #919eab;
    padding-top: var(--s6); display: flex; align-items: center; justify-content: center; gap: 6px;
  }
  footer .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--primary); }
  footer.offline { color: var(--red); }
  footer.offline .dot { background: var(--red); }

  /* ---- Live terminal ---- */
  #terminal {
    position: fixed; inset: 0; background: #161c24; z-index: 50;
    display: none; flex-direction: column;
    padding: max(var(--s4), env(safe-area-inset-top)) var(--s4) max(var(--s4), env(safe-area-inset-bottom));
  }
  #terminal.open { display: flex; }
  #terminal .thead { display: flex; align-items: center; gap: var(--s3); margin-bottom: var(--s3); }
  #terminal .tname { font-size: var(--fs-sm); font-weight: 700; color: #fff; }
  #terminal .tclose {
    margin-left: auto; background: rgba(255,255,255,.12); color: #fff; border: none;
    border-radius: var(--r-ctl); padding: 9px 14px; font-family: inherit; font-size: var(--fs-xs);
    font-weight: 600; cursor: pointer;
  }
  #terminal .tclose:hover { background: rgba(255,255,255,.2); }
  .term {
    flex: 1; min-height: 0; overflow: auto; background: #0b0e13; color: #d6dde5;
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 11.5px; line-height: 1.4;
    white-space: pre; -webkit-overflow-scrolling: touch; overscroll-behavior: contain;
    border-radius: var(--r-ctl); padding: var(--s4);
  }
  .keys { display: flex; flex-wrap: wrap; gap: var(--s2); margin: var(--s3) 0; }
  .keys button {
    background: rgba(255,255,255,.1); color: #fff; border: none; border-radius: var(--r-ctl);
    padding: 11px var(--s4); font-family: inherit; font-size: var(--fs-xs); font-weight: 600;
    min-width: 46px; cursor: pointer; transition: background var(--dur-fast);
  }
  .keys button:hover { background: rgba(255,255,255,.18); }
  .keys button:active { background: rgba(255,255,255,.28); }
  .keys button.y { background: rgba(0,167,111,.25); color: var(--primary-light); }
  .keys button.n { background: rgba(255,86,48,.22); color: #ffac9b; }
  .tinput { display: flex; gap: var(--s3); }
  .tinput input { background: rgba(255,255,255,.06); border-color: rgba(255,255,255,.14); color: #fff; }
  .tinput input::placeholder { color: #8b96a3; }
  .tinput input:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(0,167,111,.25); }

  /* ---- Keyboard focus (a11y) ---- */
  :focus-visible {
    outline: 2px solid var(--primary); outline-offset: 2px; border-radius: 4px;
  }
  button:focus-visible { outline-offset: 3px; }
</style>
</head>
<body>
<header>
  <div class="logo">🌱</div>
  <div>
    <h1>AgentGarden</h1>
    <div class="sub">remote agent control</div>
  </div>
  <span class="count" id="count"></span>
</header>
<div id="usage"></div>
<div id="approvals"></div>
<main id="list"></main>
<div id="terminal"></div>
<footer id="foot"><span class="dot"></span><span id="foottext"></span></footer>
<script>
const list = document.getElementById('list');
const count = document.getElementById('count');
const foot = document.getElementById('foot');
const footText = document.getElementById('foottext');

// Token comes in via the link you open from the Mac app (?token=…) and rides
// along on every API call. The page shell + avatars are public.
const TOKEN = new URLSearchParams(location.search).get('token') || '';
const AUTH = { 'Authorization': 'Bearer ' + TOKEN };
function auth(extra) { return Object.assign({}, AUTH, extra || {}); }
let openTerm = null;   // agent id whose live terminal is on screen

// --- Avatars: stable-random per agent id so it never flickers between ticks ---
const AVATARS = ['avatar-9', 'avatar-10', 'avatar-11', 'avatar-12', 'avatar-13'];
function hashStr(s) { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return Math.abs(h); }
function avatarSrc(id) { return '/avatar/' + AVATARS[hashStr(id) % AVATARS.length] + '.webp'; }

function statusClass(a) {
  if (a.isError) return 'err';
  if (a.isDone) return 'done';
  if (a.needsAttention) return 'attn';
  return 'run';
}
function label(a) {
  if (a.isError) return 'Error';
  if (a.isDone) return 'Selesai';
  if (a.needsAttention) return 'Butuh input';
  return 'Berjalan';
}
function elapsed(iso) {
  const s = Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 1000));
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s / 60) + 'm';
  return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
}
function avatar(a) {
  const st = statusClass(a);
  const initial = esc((a.id[0] || '?').toUpperCase());
  return `<div class="avatar">
      <img src="${avatarSrc(a.id)}" alt="" loading="lazy"
           onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
      <span class="fallback">${initial}</span>
      <span class="badge ${st}"></span>
    </div>`;
}
function render(agents) {
  count.textContent = agents.length ? agents.length + ' agent' : '';
  // Don't clobber the DOM while you're typing a prompt into a card.
  const active = document.activeElement;
  if (active && active.classList && active.classList.contains('cin')) return;
  if (!agents.length) {
    list.innerHTML = '<div class="empty">' +
      '<div class="ico">🌱</div>' +
      'Belum ada agen yang jalan.<br>Mulai sesi Claude Code di Mac lo.</div>';
    return;
  }
  list.innerHTML = agents.map(a => {
    const cls = a.isError ? 'error' : (a.needsAttention ? 'attention' : '');
    return `
    <div class="plot">
      <div class="card ${cls}">
        ${avatar(a)}
        <div class="info">
          <div class="name">${esc(a.id)}</div>
          ${a.task ? `<div class="task">${esc(a.task)}</div>` : ''}
          <div class="state">${label(a)}${a.lastTool ? ` <span class="tool">· ${esc(a.lastTool)}</span>` : ''}</div>
        </div>
        <div class="meta">
          <span class="age">${elapsed(a.startedAt)}</span>
          <button class="tbtn" title="Live terminal" aria-label="Buka terminal ${esc(a.id)}" onclick="openTerminal('${esc(a.id)}')">⌨</button>
        </div>
      </div>
      <div class="compose">
        <input class="cin" type="text" enterkeyhint="send" aria-label="Prompt untuk ${esc(a.id)}"
               placeholder="kirim prompt ke ${esc(a.id)}…"
               data-agent="${esc(a.id)}" onkeydown="if(event.key==='Enter')send(this)">
        <button aria-label="Kirim" onclick="send(this.previousElementSibling)">➤</button>
      </div>
    </div>`; }).join('');
}
async function send(input) {
  const agent = input.dataset.agent;
  const text = input.value.trim();
  if (!text) return;
  input.disabled = true;
  try {
    await fetch('/prompt', {
      method: 'POST',
      headers: auth({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ agent, text })
    });
    input.value = '';
  } catch {}
  input.disabled = false;
  input.blur();
  tick();
}
function esc(s) {
  return String(s).replace(/[&<>"']/g, c => '&#' + c.charCodeAt(0) + ';');
}
async function decide(id, decision, btn) {
  btn.closest('.buttons').querySelectorAll('button').forEach(b => b.disabled = true);
  try {
    await fetch('/approval/' + id + '/decide', {
      method: 'POST',
      headers: auth({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ decision })
    });
  } catch {}
  tick();
}
function renderApprovals(items) {
  const box = document.getElementById('approvals');
  if (!items.length) { box.innerHTML = ''; return; }
  box.innerHTML = items.map(a => `
    <div class="approval">
      <div class="who">⚠️ <b>${esc(a.agent)}</b> mau pakai ${esc(a.tool)}</div>
      <div class="cmd">${esc(a.detail)}</div>
      <div class="buttons">
        <button class="allow" onclick="decide('${a.id}','allow',this)">Approve</button>
        <button class="deny" onclick="decide('${a.id}','deny',this)">Deny</button>
      </div>
    </div>`).join('');
}
// --- Live terminal (tmux bridge) ---
function openTerminal(id) {
  openTerm = id;
  const t = document.getElementById('terminal');
  t.innerHTML = `
    <div class="thead">
      <span class="tname">⌨ ${esc(id)}</span>
      <button class="tclose" onclick="closeTerminal()">tutup ✕</button>
    </div>
    <pre class="term" id="termscreen">memuat…</pre>
    <div class="keys">
      <button class="y" onclick="sendKeys(['1','Enter'])">1·Yes</button>
      <button class="n" onclick="sendKeys(['2','Enter'])">2·No</button>
      <button onclick="sendKeys(['3','Enter'])">3</button>
      <button onclick="sendKeys(['y'])">y</button>
      <button onclick="sendKeys(['n'])">n</button>
      <button onclick="sendKeys(['Up'])">↑</button>
      <button onclick="sendKeys(['Down'])">↓</button>
      <button onclick="sendKeys(['Enter'])">⏎ Enter</button>
      <button onclick="sendKeys(['Escape'])">esc</button>
    </div>
    <div class="tinput">
      <input class="cin" id="tin" enterkeyhint="send" placeholder="ketik ke terminal…"
             onkeydown="if(event.key==='Enter')sendText()">
      <button onclick="sendText()">➤</button>
    </div>`;
  t.classList.add('open');
  refreshTerminal();
}
function closeTerminal() {
  openTerm = null;
  document.getElementById('terminal').classList.remove('open');
}
async function refreshTerminal() {
  if (!openTerm) return;
  try {
    const r = await fetch('/terminal/' + encodeURIComponent(openTerm), { headers: AUTH });
    const j = await r.json();
    const pre = document.getElementById('termscreen');
    if (pre) {
      const atBottom = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 24;
      pre.textContent = j.screen || '(terminal kosong — jalanin sesi via garden-claude.sh)';
      if (atBottom) pre.scrollTop = pre.scrollHeight;
    }
  } catch {}
}
async function sendKeys(keys) {
  if (!openTerm) return;
  try {
    await fetch('/keys', {
      method: 'POST',
      headers: auth({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ agent: openTerm, keys })
    });
  } catch {}
  setTimeout(refreshTerminal, 250);
}
function sendText() {
  const inp = document.getElementById('tin');
  if (!inp || !inp.value) return;
  const text = inp.value;
  inp.value = '';
  sendKeys([text, 'Enter']);
}

function renderUsage(u) {
  const el = document.getElementById('usage');
  if (!u || u.today == null) { el.innerHTML = ''; return; }
  const pct = Math.min(u.pct, 1);
  const col = u.pct >= 1 ? '#ff5252' : (u.pct >= 0.8 ? '#ffb020' : '#3ddc84');
  const warn = u.pct >= 1 ? 'OVER BUDGET' : (u.pct >= 0.8 ? 'tinggal dikit' : '');
  const top = (u.byModel && u.byModel[0]) ? u.byModel[0].model.replace('claude-', '') : '';
  const days = u.days || [];
  const maxv = Math.max(...days.map(d => d.cost), 0.0001);
  const bars = days.map(d =>
    `<div style="flex:1;background:${col};opacity:.75;border-radius:1px;height:${Math.max(2, 16 * d.cost / maxv)}px"></div>`).join('');
  el.innerHTML =
    `<div style="margin:8px 12px;padding:10px 12px;background:rgba(255,255,255,.05);border-radius:12px">
       <div style="display:flex;justify-content:space-between;align-items:center;font:600 11px monospace">
         <span style="color:#9aa">MODEL SPEND HARI INI</span>
         <span style="color:${col}">$${u.today.toFixed(2)} / $${u.budget.toFixed(0)}</span>
       </div>
       <div style="height:7px;background:rgba(255,255,255,.08);border-radius:4px;margin-top:6px;overflow:hidden">
         <div style="height:100%;width:${(pct * 100).toFixed(1)}%;background:${col};border-radius:4px"></div>
       </div>
       <div style="display:flex;align-items:flex-end;gap:2px;margin-top:6px;height:18px">
         <span style="font:700 9px monospace;color:${col};align-self:center">${warn}</span>
         <span style="flex:1"></span>
         <span style="font:9px monospace;color:#778;align-self:center;margin-right:6px">${top}</span>
         <div style="display:flex;align-items:flex-end;gap:2px;height:16px;width:70px">${bars}</div>
       </div>
     </div>`;
}

async function tick() {
  try {
    const [ra, rp, ru] = await Promise.all([
      fetch('/agents', { headers: AUTH }),
      fetch('/approvals', { headers: AUTH }),
      fetch('/usage', { headers: AUTH })
    ]);
    if (ra.status === 401 || rp.status === 401) {
      footText.textContent = 'token salah/hilang — buka ulang link dari app';
      foot.classList.add('offline');
      return;
    }
    render(await ra.json());
    renderApprovals(await rp.json());
    try { renderUsage(await ru.json()); } catch {}
    if (openTerm) refreshTerminal();
    footText.textContent = 'AgentGarden · live';
    foot.classList.remove('offline');
  } catch {
    footText.textContent = 'koneksi ke Mac putus — cek Tailscale';
    foot.classList.add('offline');
  }
}
tick();
setInterval(tick, 1500);
</script>
</body>
</html>
"""#
}
