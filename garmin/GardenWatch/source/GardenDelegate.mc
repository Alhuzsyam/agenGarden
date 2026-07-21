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

    // START / tap: if the current agent is waiting, ask Allow or Deny.
    function onSelect() {
        var id = view.currentApprovalId();
        if (id != null) {
            var menu = new WatchUi.Menu2({ :title => "Approve?" });
            menu.addItem(new WatchUi.MenuItem("Allow", null, :allow, null));
            menu.addItem(new WatchUi.MenuItem("Deny", null, :deny, null));
            WatchUi.pushView(menu, new ApproveMenuDelegate(view, id), WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// Handles the Allow/Deny menu: posts the verdict and pops back.
class ApproveMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view;
    var id;

    function initialize(v, approvalId) {
        Menu2InputDelegate.initialize();
        view = v;
        id = approvalId;
    }

    function onSelect(item) {
        view.decide(id, item.getId() == :allow ? "allow" : "deny");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
