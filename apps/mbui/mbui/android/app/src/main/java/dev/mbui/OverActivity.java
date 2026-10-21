package dev.mbui;

/**
 * The app over another app (a share sheet over the app something is shared from, as still.fail's ShareActivity): the
 * same app in an activity of its own, which the app's manifest declares with a translucent theme, a task of its own and
 * out of the recent apps, and the intents it takes (ACTION_SEND). Its view draws only what the app puts over the app
 * under it (the app is told it is over another: src/host/system.mbt `over`); the app ends it (@host.over_done), going
 * back where the person was or on into the app's own activity. The app's view moves to it while it is shown and back
 * to MainActivity's as that is resumed (MBView: each view's drawing set up again in its own context).
 */
public class OverActivity extends MainActivity {
    @Override
    boolean over() {
        return true;
    }

    @Override
    public void finish() {
        super.finish();
        // the sheet went with its own motion: no other on top of it
        overridePendingTransition(0, 0);
    }
}
