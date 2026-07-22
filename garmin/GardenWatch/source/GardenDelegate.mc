using Toybox.WatchUi;

// Paging + approve. Swipe left/right (touch) or up/down buttons move between
// agents. START on a waiting agent opens an Allow/Deny menu. BACK exits.
class GardenDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(v) {
        BehaviorDelegate.initialize();
        view = v;
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
