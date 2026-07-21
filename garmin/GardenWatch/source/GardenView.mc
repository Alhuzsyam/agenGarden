using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Attention;
using Toybox.Lang;

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
    var usageLoaded = false;
    var buzzedBudget = false;

    function initialize() { View.initialize(); }

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
            usageTop = (bm instanceof Lang.Array && bm.size() > 0) ? bm[0]["model"].toString() : "";
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

    function totalPages() { return agents.size() + 1; }   // agents + 1 usage page

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
            for (var i = 0; i < data.size(); i++) {
                var ap = data[i];
                var ag = ap["agent"];
                if (ag != null) { m[ag] = ap["id"]; }
            }
            approvals = m;
            WatchUi.requestUpdate();
        }
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

    function drawUsagePage(dc, cx, w, h) {
        var col = usageColor();
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 66, Graphics.FONT_TINY, "SPEND HARI INI", mid);

        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 118, Graphics.FONT_NUMBER_MEDIUM, "$" + usageToday.format("%.2f"), mid);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 165, Graphics.FONT_TINY, "budget $" + usageBudget.format("%.0f"), mid);

        // progress bar
        var bw = 220;
        var bx = cx - bw / 2;
        var by = 190;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, 12);
        var p = usagePct;
        if (p > 1.0) { p = 1.0; }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, (bw * p).toNumber(), 12);

        if (usagePct >= 0.8) {
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 228, Graphics.FONT_SMALL,
                usagePct >= 1.0 ? "OVER BUDGET" : "tinggal dikit", mid);
        }

        drawSpark(dc, cx, 296, col);   // bars grow UP from this baseline
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

        // last page (or empty garden) = usage/spend summary
        if (index >= agents.size()) {
            drawUsagePage(dc, cx, w, h);
            drawPellets(dc, cx, 322, totalPages(), index);
            return;
        }

        var a = agents[index];
        var st = stateOf(a);
        var color = st[1];
        var attn = truthy(a, "needsAttention");
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // hero (centered at y=100): ghost when it needs you, else chomping Pac-Man
        if (attn) {
            drawGhostPixel(dc, cx, 100, 11, Graphics.COLOR_RED);
        } else {
            drawPacmanPixel(dc, cx, 100, 60, 12, color, k);
        }

        // evenly-spaced text rows, all vertically centered on their y
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 200, Graphics.FONT_MEDIUM, trunc(str(a, "id", "agent"), 16), mid);

        if (!attn || animPhase < 6) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 240, Graphics.FONT_SMALL, st[0], mid);
        }

        if (currentApprovalId() != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 274, Graphics.FONT_XTINY, "START = approve", mid);
        }

        drawPellets(dc, cx, 322, totalPages(), index);
    }
}
