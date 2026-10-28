import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PokeWatchApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var v = new GameView();
        return [v, new GameDelegate(v)];
    }
}
