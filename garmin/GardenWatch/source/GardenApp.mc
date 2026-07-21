using Toybox.Application;
using Toybox.WatchUi;

// AgentGarden watch mirror — no-touch. Shows whether any tool is waiting for
// approval and buzzes your wrist when one appears. It does NOT approve or type;
// you still do that on the phone. Real-time only while this app is open on the
// watch (Connect IQ background services are capped at ~5 min, which is longer
// than the 280s approval window — see the README).
class GardenApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {}
    function onStop(state) {}

    function getInitialView() {
        var view = new GardenView();
        return [ view, new GardenDelegate(view) ];
    }
}
