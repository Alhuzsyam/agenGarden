using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Attention;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

// Pixel-art arcade dashboard. One agent per page; swipe to move. Hero sprite is
// a pixelated Pac-Man that chomps (colored by state); when an agent needs you
// it becomes a red arcade GHOST. Minimal text: name + one status word + pellet
// page-dots. Press START on a waiting agent to Allow/Deny from the wrist.
class GardenView extends WatchUi.View {
    var agents = [];
    var approvals = {};      // agentName => approval id (pending)
    var index = 0;
    var lastCode = 0;
    var status = "connecting…";
    var pollTimer = null;
    var animTimer = null;
    var animPhase = 0;
    var buzzed = false;
    // usage (last swipe page)
    var usageToday = 0.0;
    var usageBudget = 0.0;
    var usagePct = 0.0;
    var usageSpark = [];
    var usageTop = "";
    var usageModelNames = [];
    var usageModelCosts = [];
    var usageLoaded = false;
    var buzzedBudget = false;
    // approval face
    var pendId = null;
    var pendAgent = null;
    var pendTool = null;
    var pendDetail = null;
    var pendSeenAt = 0;      // device epoch secs when this approval first seen
    var waitCount = 0;
    var buzzedApproval = false;
    var successUntil = 0;    // device epoch secs; idle face celebrates until then
    var monoS = null;        // custom Roboto Mono font (loaded in onLayout)
    var monoXS = null;

    function initialize() { View.initialize(); }

    function onLayout(dc) {
        monoS = WatchUi.loadResource(Rez.Fonts.MonoS);
        monoXS = WatchUi.loadResource(Rez.Fonts.MonoXS);
    }

    function onShow() {
        pollTimer = new Timer.Timer();
        pollTimer.start(method(:poll), Config.POLL_MS, true);
        animTimer = new Timer.Timer();
        animTimer.start(method(:animate), 140, true);
        poll();
    }

    function onHide() {
        if (pollTimer != null) { pollTimer.stop(); pollTimer = null; }
        if (animTimer != null) { animTimer.stop(); animTimer = null; }
    }

    function animate() {
        animPhase = (animPhase + 1) % 10;
        WatchUi.requestUpdate();
    }

    function getOpts() {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Authorization" => "Bearer " + Config.GARDEN_TOKEN },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function poll() {
        Communications.makeWebRequest(Config.GARDEN_URL + "/agents", null, getOpts(), method(:onAgents));
        Communications.makeWebRequest(Config.GARDEN_URL + "/approvals", null, getOpts(), method(:onApprovals));
        Communications.makeWebRequest(Config.GARDEN_URL + "/usage", null, getOpts(), method(:onUsage));
    }

    function fnum(v) { return v == null ? 0.0 : v.toFloat(); }

    function onUsage(code, data) {
        if (code == 200 && data instanceof Lang.Dictionary) {
            usageToday = fnum(data["today"]);
            usageBudget = fnum(data["budget"]);
            usagePct = fnum(data["pct"]);
            var bm = data["byModel"];
            var names = [];
            var costs = [];
            if (bm instanceof Lang.Array) {
                for (var i = 0; i < bm.size(); i++) {
                    names.add(bm[i]["model"].toString());
                    costs.add(fnum(bm[i]["cost"]));
                }
            }
            usageModelNames = names;
            usageModelCosts = costs;
            usageTop = names.size() > 0 ? names[0] : "";
            var days = data["days"];
            var sp = [];
            if (days instanceof Lang.Array) {
                for (var i = 0; i < days.size(); i++) { sp.add(fnum(days[i]["cost"])); }
            }
            usageSpark = sp;
            usageLoaded = true;
            if (usagePct >= 1.0 && !buzzedBudget) { buzz(); buzzedBudget = true; }
            if (usagePct < 1.0) { buzzedBudget = false; }
            WatchUi.requestUpdate();
        }
    }

    function totalPages() { return 3; }   // 0 = approval/idle face · 1 = agents list · 2 = usage

    function onAgents(code, data) {
        lastCode = code;
        if (code == 200 && data instanceof Lang.Array) {
            agents = data;
            if (index > agents.size()) { index = agents.size(); }   // keep usage page reachable
            var anyAttn = false;
            for (var i = 0; i < agents.size(); i++) {
                if (truthy(agents[i], "needsAttention")) { anyAttn = true; }
            }
            if (anyAttn && !buzzed) { buzz(); buzzed = true; }
            if (!anyAttn) { buzzed = false; }
            status = null;
        } else if (code < 0) {
            status = "no link";
        } else {
            status = "HTTP " + code.toString();
        }
        WatchUi.requestUpdate();
    }

    function onApprovals(code, data) {
        if (code == 200 && data instanceof Lang.Array) {
            var m = {};
            var firstId = null;
            var firstAgent = null;
            var firstTool = null;
            var firstDetail = null;
            for (var i = 0; i < data.size(); i++) {
                var ap = data[i];
                var ag = ap["agent"];
                if (ag != null) { m[ag] = ap["id"]; }
                if (i == 0) {
                    firstId = ap["id"];
                    firstAgent = ag;
                    firstTool = ap["tool"];
                    firstDetail = ap["detail"];
                }
            }
            approvals = m;
            waitCount = data.size();
            if (firstId != null && !firstId.equals(pendId == null ? "" : pendId)) {
                pendSeenAt = Time.now().value();   // reset countdown on a NEW approval
                index = 0;                         // jump to the approval face so it's decidable
            }
            pendId = firstId;
            pendAgent = firstAgent;
            pendTool = firstTool;
            pendDetail = firstDetail;
            if (pendId != null && !buzzedApproval) { buzz(); buzzedApproval = true; }
            if (pendId == null) { buzzedApproval = false; }
            WatchUi.requestUpdate();
        }
    }

    function pendingApprovalActive() { return index == 0 && pendId != null; }
    function decideCurrent(v) {
        if (pendId != null) {
            if (v.equals("allow")) { successUntil = Time.now().value() + 3; }
            decide(pendId, v);
        }
    }
    function riskInfo() {
        var d = ((pendDetail == null ? "" : pendDetail) + " " + (pendTool == null ? "" : pendTool)).toLower();
        if (d.find("--force") != null || d.find("rm ") != null || d.find("push") != null
            || d.find("sudo") != null || d.find("delete") != null || d.find("drop") != null) {
            return ["HIGH", 0xF28B82];
        }
        if (d.find("edit") != null || d.find("write") != null) { return ["MED", 0xFDD835]; }
        return ["LOW", 0x8AB4F8];
    }
    function remainSec() {
        if (pendId == null) { return 0; }
        var rem = 280 - (Time.now().value() - pendSeenAt);
        return rem < 0 ? 0 : rem;
    }

    // POST a verdict from the wrist.
    function decide(id, verdict) {
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer " + Config.GARDEN_TOKEN
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(
            Config.GARDEN_URL + "/approval/" + id + "/decide",
            { "decision" => verdict }, opts, method(:onDecide));
    }
    function onDecide(code, data) {
        poll();   // refresh right away so the ghost clears
    }

    function currentApprovalId() {
        if (agents.size() == 0 || index >= agents.size()) { return null; }
        var ag = agents[index]["id"];
        if (ag == null) { return null; }
        return approvals[ag];   // null if none pending
    }

    function next() { var t = totalPages(); if (t > 0) { index = (index + 1) % t; WatchUi.requestUpdate(); } }
    function prev() { var t = totalPages(); if (t > 0) { index = (index - 1 + t) % t; WatchUi.requestUpdate(); } }

    // ---- helpers ----
    function truthy(a, key) { var v = a[key]; return v != null && v == true; }
    function str(a, key, dflt) { var v = a[key]; return (v == null) ? dflt : v.toString(); }
    function trunc(s, n) { return s.length() <= n ? s : s.substring(0, n - 1) + "…"; }
    function wrap(s, perLine, maxLines) {
        var lines = [];
        var rest = s;
        while (rest.length() > 0 && lines.size() < maxLines) {
            if (rest.length() <= perLine) { lines.add(rest); break; }
            lines.add(rest.substring(0, perLine));
            rest = rest.substring(perLine, rest.length());
        }
        if (rest.length() > perLine && lines.size() == maxLines) {
            lines[maxLines - 1] = lines[maxLines - 1].substring(0, perLine - 1) + "…";
        }
        return lines;
    }

    function stateOf(a) {
        if (truthy(a, "isError"))        { return ["GAME OVER", Graphics.COLOR_RED]; }
        if (truthy(a, "needsAttention")) { return ["BUTUH KAMU", Graphics.COLOR_RED]; }
        if (truthy(a, "isDone"))         { return ["SELESAI", Graphics.COLOR_DK_GRAY]; }
        return ["JALAN", Graphics.COLOR_YELLOW];
    }

    function mouthOpen() {
        var t = animPhase < 5 ? animPhase : 10 - animPhase;
        return t / 5.0;
    }

    // Pixel Pac-Man: grid of squares carved from a circle minus a mouth wedge.
    function drawPacmanPixel(dc, cx, cy, r, px, color, k) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var r2 = r * r;
        var start = -(((r / px) + 1) * px);
        for (var gx = start; gx <= r; gx += px) {
            for (var gy = start; gy <= r; gy += px) {
                var ccx = gx + px / 2;
                var ccy = gy + px / 2;
                if (ccx * ccx + ccy * ccy > r2) { continue; }
                var ay = ccy < 0 ? -ccy : ccy;
                if (ccx > 0 && ay <= k * ccx) { continue; }
                if (gx == -px && gy == -(((r / px) / 2) * px)) { continue; }   // eye
                dc.fillRectangle(cx + gx, cy + gy, px - 2, px - 2);
            }
        }
    }

    // Pixel arcade ghost. '1' body, '2' eye white, '3' pupil, '0' empty.
    function drawGhostPixel(dc, cx, cy, px, body) {
        var rows = [
            "000111111000",
            "001111111100",
            "011111111110",
            "111111111111",
            "110220110220",
            "110330110330",
            "111111111111",
            "111111111111",
            "111111111111",
            "111111111111",
            "101101101101"
        ];
        var cols = 12;
        var x0 = cx - (cols * px) / 2;
        var y0 = cy - (rows.size() * px) / 2;
        for (var r = 0; r < rows.size(); r++) {
            var row = rows[r];
            for (var c = 0; c < cols; c++) {
                var ch = row.substring(c, c + 1);
                if (ch.equals("0")) { continue; }
                if (ch.equals("2")) { dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT); }
                else if (ch.equals("3")) { dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT); }
                else { dc.setColor(body, Graphics.COLOR_TRANSPARENT); }
                dc.fillRectangle(x0 + c * px, y0 + r * px, px - 1, px - 1);
            }
        }
    }

    function drawPellets(dc, cx, y, n, cur) {
        if (n <= 0) { return; }
        var gap = n > 10 ? 12 : 16;
        var x0 = cx - ((n - 1) * gap) / 2;
        for (var i = 0; i < n; i++) {
            var x = x0 + i * gap;
            if (i == cur) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 4, y - 4, 8, 8);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 2, y - 2, 4, 4);
            }
        }
    }

    function buzz() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 500),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 500)
            ]);
        }
    }

    function usageColor() {
        if (usagePct >= 1.0) { return Graphics.COLOR_RED; }
        if (usagePct >= 0.8) { return Graphics.COLOR_YELLOW; }
        return Graphics.COLOR_GREEN;
    }

    function drawSpark(dc, cx, y, color) {
        var n = usageSpark.size();
        if (n == 0) { return; }
        var maxv = 0.0001;
        for (var i = 0; i < n; i++) { if (usageSpark[i] > maxv) { maxv = usageSpark[i]; } }
        var bw = 10;
        var gap = 4;
        var totalW = n * (bw + gap) - gap;
        var x0 = cx - totalW / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            var hgt = (28 * usageSpark[i] / maxv).toNumber();
            if (hgt < 2) { hgt = 2; }
            dc.fillRectangle(x0 + i * (bw + gap), y - hgt, bw, hgt);
        }
    }

    // A HALF-circle (top semicircle) arc: darker track over the top 180°, then a
    // colored arc filling from the left (9 o'clock) by `frac`.
    function drawSemiRing(dc, cx, cy, r, frac, color) {
        var f = frac;
        if (f < 0) { f = 0; }
        if (f > 1.0) { f = 1.0; }
        dc.setPenWidth(15);
        dc.setColor(0xC77B22, Graphics.COLOR_TRANSPARENT);   // darker-orange track
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 180, 0);   // top half
        if (f > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 180, 180 - 180 * f);
        }
        dc.setPenWidth(1);
    }

    function shortModel(m) {
        if (m == null) { return "?"; }
        var i = m.find("claude-");
        return (i != null && i == 0) ? m.substring(7, m.length()) : m;
    }

    // "AgentGarden" with a small Pac-Man chomping across it, left to right, on
    // loop. Draws the word (green), erases the part left of Pac-Man with the
    // background, then draws the little chomper at the eating edge.
    // Solid (smooth) Pac-Man: filled circle with a wedge mouth cut to the
    // background, plus an eye. Chomps as `open` (0..1) animates.
    function drawPacmanSolid(dc, cx, cy, r, color, open) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        var half = (r * (12 + (open * 60).toNumber())) / 100;
        var mx = cx + r + 3;
        dc.setColor(0x16161E, Graphics.COLOR_TRANSPARENT);   // cut mouth to bg
        dc.fillPolygon([[cx, cy], [mx, cy - half], [mx, cy + half]]);
        dc.fillCircle(cx - r / 5, cy - r / 2, r / 6);         // eye
    }

    // Page 2 — model spend, notouch dark+mono style: a segmented ring per model,
    // today's total in the centre, model + budget status below. Proportional:
    // ring hero, big $ total, then smaller model/budget lines.
    function drawUsagePage(dc, cx, w, h) {
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var palette = [0xBADC58, 0xF5F5F5, 0x8AB4F8, 0x8B8B99, 0x5A5A66];
        var cy = 150;
        var r = 96;
        var bcol = usagePct >= 1.0 ? 0xEA4335 : (usagePct >= 0.8 ? 0xFDD835 : 0xBADC58);

        dc.setColor(0x16161E, 0x16161E);
        dc.clear();

        // track + per-model segments
        dc.setPenWidth(18);
        dc.setColor(0x2B2B36, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, -269);
        var total = usageToday > 0 ? usageToday : 0.0001;
        var n = usageModelCosts.size();
        if (n > 5) { n = 5; }
        var startDeg = 90.0;
        for (var i = 0; i < n; i++) {
            var frac = usageModelCosts[i] / total;
            if (frac > 0.001) {
                var endDeg = startDeg - 360.0 * frac;
                dc.setColor(palette[i], Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, endDeg);
                startDeg = endDeg;
            }
        }
        dc.setPenWidth(1);

        // centre: big $ total + "today"
        if (!usageLoaded) {
            dc.setColor(0x8B8B99, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, fSmall(), "loading…", mid);
        } else {
            dc.setColor(bcol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 12, fTitle(), "$" + usageToday.format("%.2f"), mid);
            dc.setColor(0x8B8B99, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 20, fSmall(), "today", mid);
        }

        // below ring: top model (kept) + budget status
        dc.setColor(0xBADC58, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 268, fSmall(), shortModel(usageTop), mid);
        var status = usagePct >= 1.0 ? "OVER BUDGET"
                   : (usagePct >= 0.8 ? "tinggal dikit"
                   : "$" + usageBudget.format("%.0f") + " budget");
        dc.setColor(usagePct >= 0.8 ? bcol : 0x8B8B99, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 294, fSmall(), status, mid);
    }

    // ---- drawing ----
    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var k = 0.05 + mouthOpen() * 0.9;

        if (status != null) {
            drawPacmanPixel(dc, cx, h / 2 - 26, 60, 11, Graphics.COLOR_YELLOW, k);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2 + 44, Graphics.FONT_SMALL, status, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // page 1 = full agent list · page 2 = usage (spend rings)
        if (index == 1) {
            drawAgentsList(dc, cx, w, h);
            drawPellets(dc, cx, 322, 3, index);
            return;
        }
        if (index == 2) {
            drawUsagePage(dc, cx, w, h);
            drawPellets(dc, cx, 322, 3, index);
            return;
        }

        // page 0 = approval prompt if something's waiting, else idle "All clear"
        if (pendId != null) {
            drawApprovalFace(dc, cx, h);
        } else {
            drawIdleFace(dc, cx, h);
        }
        drawPellets(dc, cx, 322, 3, index);
    }

    // Page 1 — every agent as a row: status dot + name + short state. Shows up to
    // 5, then a "+N more" tail so nothing is hidden from the count.
    function drawAgentsList(dc, cx, w, h) {
        var midL = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var midR = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 74, fSmall(), "AGENTS · " + agents.size().format("%d"), mid);

        if (agents.size() == 0) {
            dc.setColor(0x8AB4F8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 190, fTitle(), "No agents", mid);
            return;
        }

        var n = agents.size();
        var shown = n > 5 ? 5 : n;
        var y = 118;
        for (var i = 0; i < shown; i++) {
            var a = agents[i];
            var st = stateOf(a);                       // [label, color]
            var short = "run";
            if (truthy(a, "isError"))            { short = "err"; }
            else if (truthy(a, "needsAttention")) { short = "wait"; }
            else if (truthy(a, "isDone"))         { short = "done"; }
            dc.setColor(st[1], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(70, y, 6);
            dc.setColor(0xF4F4F8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(88, y, fSmall(), trunc(str(a, "id", "agent"), 13), midL);
            dc.setColor(st[1], Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - 60, y, fSmall(), short, midR);
            y += 40;
        }
        if (n > 5) {
            dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + 2, fSmall(), "+" + (n - 5).format("%d") + " more", mid);
        }
    }

    // Design face #1 — approval prompt: red countdown ring, risk + timer, agent,
    // command, and ✕ / ✓ buttons.
    function drawApprovalFace(dc, cx, h) {
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var cy = 195;
        var ri = riskInfo();
        var s = remainSec();
        var frac = s / 280.0;

        // countdown ring
        dc.setPenWidth(12);
        dc.setColor(0x2A2A2C, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, 150, Graphics.ARC_CLOCKWISE, 90, -269);
        if (frac > 0) {
            dc.setColor(0xEA4335, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, 150, Graphics.ARC_CLOCKWISE, 90, 90 - 360 * frac);
        }
        dc.setPenWidth(1);

        // risk · countdown
        var cd = (s / 60).format("%d") + ":" + (s % 60).format("%02d");
        dc.setColor(ri[1], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 106, fSmall(), "● " + ri[0] + " · " + cd, mid);

        // agent (yellow)
        dc.setColor(0xFDD835, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 140, fTitle(), pendAgent == null ? "?" : pendAgent.toString(), mid);

        // command (white, up to 2 lines) — mono is wider, so wrap tighter
        var lines = wrap(pendDetail == null ? "" : pendDetail.toString(), 16, 2);
        dc.setColor(0xE8EAED, Graphics.COLOR_TRANSPARENT);
        var ty = 176;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, ty, fSmall(), lines[i], mid);
            ty += 22;
        }

        // buttons: ✕ deny (left, red) · ✓ allow (right, green)
        var by = 268;
        var lxx = cx - 46;
        var rxx = cx + 46;
        dc.setColor(0xEA4335, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(lxx, by, 27);
        dc.setColor(0x34A853, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(rxx, by, 27);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(lxx - 9, by - 9, lxx + 9, by + 9);
        dc.drawLine(lxx - 9, by + 9, lxx + 9, by - 9);
        dc.drawLine(rxx - 10, by, rxx - 2, by + 8);
        dc.drawLine(rxx - 2, by + 8, rxx + 11, by - 9);
        dc.setPenWidth(1);

        // button hints so you know which physical key does what
        dc.setColor(0x8B8B99, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lxx, by + 40, fSmall(), "BACK", mid);
        dc.drawText(rxx, by + 40, fSmall(), "START", mid);
    }

    // Font helpers — prefer bundled Roboto Mono, fall back to the system fonts.
    function fTitle() { return monoS == null ? Graphics.FONT_SMALL : monoS; }
    function fSmall() { return monoXS == null ? Graphics.FONT_XTINY : monoXS; }

    // Design face #2 — idle. Mascot picks an expression to match the web:
    // idle → chasing a ghost, success → sparkles, empty → sleeping (zzz).
    // Text hierarchy stays proportional: mascot biggest, then title, then the
    // smaller count line, then the clock (same size as the title).
    function drawIdleFace(dc, cx, h) {
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var mode = "idle";
        if (agents.size() == 0)                 { mode = "empty"; }
        else if (Time.now().value() < successUntil) { mode = "success"; }

        var cy = 122;
        var r = 44;
        if (mode.equals("idle")) { drawGhostMini(dc, cx + 64, cy - 2, 17); }
        drawPacmanSolid(dc, cx, cy, r, 0xFDD835, 0.05 + mouthOpen() * 0.9);
        if (mode.equals("success")) { drawSparkles(dc, cx, cy, r); }
        if (mode.equals("empty"))   { drawZzz(dc, cx + r - 2, cy - r + 2); }

        var title = mode.equals("empty") ? "No agents"
                  : (mode.equals("success") ? "Approved!" : "All clear");
        var tcol = mode.equals("empty") ? 0x9AA0A6
                 : (mode.equals("success") ? 0x34A853 : 0x8AB4F8);
        dc.setColor(tcol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 206, fTitle(), title, mid);

        dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 242, fSmall(),
            agents.size().format("%d") + " agents · " + waitCount.format("%d") + " waiting", mid);

        var t = System.getClockTime();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 286, fTitle(),
            t.hour.format("%02d") + ":" + t.min.format("%02d"), mid);
    }

    // Small blue ghost (idle companion) — dome + scalloped skirt + eyes.
    function drawGhostMini(dc, gx, gy, r) {
        dc.setColor(0x4FC3F7, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);
        dc.fillRectangle(gx - r, gy, 2 * r + 1, r);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);          // carve skirt notches
        var yb = gy + r;
        for (var i = 0; i < 3; i++) {
            var bx = gx - r + (2 * r) * i / 3;
            var bw = (2 * r) / 3;
            dc.fillPolygon([[bx, yb], [bx + bw, yb], [bx + bw / 2, yb - 6]]);
        }
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);          // eyes
        dc.fillCircle(gx - r / 3, gy - r / 6, r / 4);
        dc.fillCircle(gx + r / 3, gy - r / 6, r / 4);
        dc.setColor(0x202124, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx - r / 3, gy - r / 6, r / 9);
        dc.fillCircle(gx + r / 3, gy - r / 6, r / 9);
    }

    // Three 4-point sparkle stars (success companion).
    function drawSparkles(dc, cx, cy, r) {
        drawStar(dc, cx - r - 6, cy - r + 4, 7, 0xFBBC04);
        drawStar(dc, cx + r + 4, cy - r + 12, 5, 0x8AB4F8);
        drawStar(dc, cx + r - 6, cy - r - 8, 4, 0x34A853);
    }
    function drawStar(dc, x, y, s, col) {
        var q = s / 3;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y - s], [x + q, y - q], [x + s, y], [x + q, y + q],
                        [x, y + s], [x - q, y + q], [x - s, y], [x - q, y - q]]);
    }

    // Rising "z z" (empty/sleeping companion).
    function drawZzz(dc, x, y) {
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, "z", c);
        dc.drawText(x + 12, y - 15, Graphics.FONT_TINY, "z", c);
    }
}
