// Input: touch follows TamaPoke's layout; button-only watches get the same
// actions through SELECT (confirm / open the action menu), UP/DOWN and BACK.
import Toybox.Lang;
import Toybox.WatchUi;

class GameDelegate extends WatchUi.BehaviorDelegate {
    private var view as GameView;

    function initialize(v as GameView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onTap(e as WatchUi.ClickEvent) as Boolean {
        var p = view.toGame(e.getCoordinates());
        view.holdEnd();
        if (view.sackOpen) {
            view.sackPress(p[1]);
        } else {
            view.tap(p[0], p[1]);
        }
        return true;
    }

    function onHold(e as WatchUi.ClickEvent) as Boolean {
        var p = view.toGame(e.getCoordinates());
        view.holdBegin(p[0], p[1]);
        return true;
    }

    function onRelease(e as WatchUi.ClickEvent) as Boolean {
        view.holdEnd();
        return true;
    }

    function onSwipe(e as WatchUi.SwipeEvent) as Boolean {
        var d = e.getDirection();
        if (d == WatchUi.SWIPE_LEFT) {
            view.swipe(-1);
        } else if (d == WatchUi.SWIPE_RIGHT) {
            // a right swipe also leaves the app on some watches: only use it inside screens
            if (!view.galleryOpen && !view.cardOpen) {
                return false;
            }
            view.swipe(1);
        } else if (d == WatchUi.SWIPE_UP) {
            view.swipeV(-1);
        } else {
            view.swipeV(1);
        }
        return true;
    }

    function onSelect() as Boolean {
        if (!view.keySelect()) {
            openMenu();
        }
        return true;
    }

    function onMenu() as Boolean {
        if (!view.blocked()) {
            openMenu();
        }
        return true;
    }

    function onBack() as Boolean {
        return view.keyBack();
    }

    function onNextPage() as Boolean {
        return view.keyPage(1);
    }

    function onPreviousPage() as Boolean {
        return view.keyPage(-1);
    }

    private function openMenu() as Void {
        var pet = view.pet;
        var m = new WatchUi.Menu2({:title => "PokeWatch"});
        if (pet.wantEvolveButton()) {
            m.addItem(new WatchUi.MenuItem(Tables.S[Str.EVO_TAP], null, :evolve, null));
        }
        if (pet.canRunawayNow() || pet.wantFarewellButton()) {
            m.addItem(new WatchUi.MenuItem(Tables.S[Str.FAR_GO], null, :farewell, null));
        }
        if (!pet.sleeping) {
            m.addItem(new WatchUi.MenuItem("Feed", null, :feed, null));
            m.addItem(new WatchUi.MenuItem("Play", null, :play, null));
            m.addItem(new WatchUi.MenuItem("Bath", null, :bath, null));
            m.addItem(new WatchUi.MenuItem("Pet", null, :caress, null));
        }
        m.addItem(new WatchUi.MenuItem(pet.sleeping ? "Lights on" : "Lights off", null, :light, null));
        m.addItem(new WatchUi.MenuItem("Stats", null, :card, null));
        m.addItem(new WatchUi.MenuItem("Pokedex", null, :dex, null));
        m.addItem(new WatchUi.MenuItem("Settings", null, :settings, null));
        m.addItem(new WatchUi.MenuItem("Release", null, :release, null));
        WatchUi.pushView(m, new ActionMenuDelegate(view), WatchUi.SLIDE_UP);
    }
}

class ActionMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var view as GameView;

    function initialize(v as GameView) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var pet = view.pet;
        if (id == :evolve) {
            view.openChoice(1);
        } else if (id == :farewell) {
            if (pet.canRunawayNow()) { pet.startRunaway(); } else { view.openChoice(2); }
        } else if (id == :feed) {
            view.openFeedMenu();
        } else if (id == :play) {
            view.startGame();
        } else if (id == :bath) {
            view.startBath();
        } else if (id == :caress) {
            view.caress();
        } else if (id == :light) {
            pet.toggleLight();
        } else if (id == :card) {
            view.openCard();
        } else if (id == :dex) {
            view.openGallery();
        } else if (id == :settings) {
            view.openSettings();
        } else if (id == :release) {
            view.askRelease();
        }
    }
}
