using Toybox.WatchUi;

// Paging + approve. UP/DOWN buttons (or swipe) move between pages. On the
// approval face: START = approve, DOWN = deny — physical buttons are more
// reliable than tapping the ✕/✓ circles while moving. BACK exits.
class GardenDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(v) {
        BehaviorDelegate.initialize();
        view = v;
    }

    // Low-level button handler: when a prompt is waiting, START approves and
    // DOWN denies. Return false otherwise so normal paging/back still works.
    function onKey(evt) {
        if (view.pendingApprovalActive()) {
            var k = evt.getKey();
            if (k == WatchUi.KEY_ENTER) { view.decideCurrent("allow"); return true; }
            if (k == WatchUi.KEY_DOWN)  { view.decideCurrent("deny");  return true; }
        }
        return false;
    }

    function onNextPage() { view.next(); return true; }
    function onPreviousPage() { view.prev(); return true; }

    function onSwipe(evt) {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_LEFT) { view.next(); }
        else if (d == WatchUi.SWIPE_RIGHT) { view.prev(); }
        return true;
    }

    // START = approve the pending prompt.
    function onSelect() {
        if (view.pendingApprovalActive()) { view.decideCurrent("allow"); }
        return true;
    }

    // Tap the ✕ (left) / ✓ (right) buttons on the approval face.
    function onTap(evt) {
        if (view.pendingApprovalActive()) {
            var c = evt.getCoordinates();
            if (c[1] > 210) {   // in the button row
                view.decideCurrent(c[0] < 195 ? "deny" : "allow");
                return true;
            }
        }
        return false;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
