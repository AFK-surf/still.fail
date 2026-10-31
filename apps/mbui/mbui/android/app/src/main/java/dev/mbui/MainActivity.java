package dev.mbui;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Build;
import android.os.Bundle;
import android.window.BackEvent;
import android.window.OnBackAnimationCallback;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import android.system.ErrnoException;
import android.system.Os;
import android.view.WindowInsets;
import android.view.WindowInsetsAnimation;
import android.view.WindowInsetsController;
import android.widget.FrameLayout;

/** Hosts one MBView inside the system bars and above the keyboard. */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        // this build's code in memory before the drawing thread comes to it (a build just installed has none of it)
        ReadAhead.start(this);
        // the GPU's driver and the codecs' list ready before the drawing thread's first frames ask for them
        WarmUp.start();
        Host.log("activity onCreate " + (saved != null ? "(restored)" : ""));
        Host.activity = this;
        // a phone upright only (Host.upright), but while the app turns it for a film
        Host.holdUpright(this);
        // `--es env K=V;K2=V2`: environment variables for the app's MoonBit (as a desktop run has them: the core
        // demo's MBUI_AUTH_BEGIN, MBUI_CORE_DUMP…), set before it starts.
        // The test hooks (env, script, bench) come in an intent any app on the device may send this exported
        // activity: a release build (the beta app) takes them only on an emulator (e2e/run.sh with E2E_APK).
        boolean hooks = testHooks();
        // The app's own defaults first (its manifest's <meta-data android:name="dev.mbui.env" android:value="K=V;…">: a
        // build's settings, as still.fail mbui's release says where its updates come from), the intent's over them.
        String defaults = null;
        try {
            Bundle meta = getPackageManager().getApplicationInfo(getPackageName(), android.content.pm.PackageManager.GET_META_DATA).metaData;
            if (meta != null) {
                defaults = meta.getString("dev.mbui.env");
                // what shows under the system bars, light and dark (<meta-data android:name="dev.mbui.ground"
                // android:value="#F5F3EF,#1B1C1F">: the app's page ground), else mbui's own
                // the app lays itself out round the system bars (<meta-data android:name="dev.mbui.edge"
                // android:value="true">): its view under them, from the screen's top to its foot, `bars` said to it
                edge = meta.getBoolean("dev.mbui.edge", false);
                String ground = meta.getString("dev.mbui.ground");
                if (ground != null && ground.indexOf(',') > 0) {
                    try {
                        Host.groundLight = Color.parseColor(ground.substring(0, ground.indexOf(',')).trim());
                        Host.groundDark = Color.parseColor(ground.substring(ground.indexOf(',') + 1).trim());
                    } catch (IllegalArgumentException e) {
                        Host.log("dev.mbui.ground " + ground + ": " + e);
                    }
                }
            }
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {}
        String given = hooks ? getIntent().getStringExtra("env") : null;
        String env = defaults == null ? given : given == null ? defaults : defaults + ";" + given;
        if (env != null) {
            for (String kv : env.split(";")) {
                int eq = kv.indexOf('=');
                if (eq <= 0) continue;
                try {
                    Os.setenv(kv.substring(0, eq), kv.substring(eq + 1), true);
                } catch (ErrnoException e) {
                    Host.log("env " + kv + ": " + e);
                }
            }
        }
        Host.openLogFile(this);
        // MBUI_CLIPBOARD (MBUI_CLIPBOARD_REPEAT times): put on the clipboard as the app starts, for pasting in scripted
        // runs (adb can type but not copy)
        String clip = System.getenv("MBUI_CLIPBOARD");
        if (clip != null && !clip.isEmpty()) {
            int times = 1;
            try { times = Integer.parseInt(System.getenv("MBUI_CLIPBOARD_REPEAT")); } catch (Exception e) {}
            StringBuilder b = new StringBuilder();
            for (int i = 0; i < Math.max(1, times); i++) b.append(clip);
            ((android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE))
                    .setPrimaryClip(android.content.ClipData.newPlainText("mbui", b.toString()));
        }
        Host.script = hooks ? getIntent().getStringExtra("script") : null;
        // a run (scripted, driven, taped: the test hooks' intent) begins with no cookies in its sites
        if (Host.script != null || given != null) NativeViews.clearCookies();
        Host.bench = hooks ? getIntent().getIntExtra("bench", 0) : 0;
        // (shot_at MS, a moment on the run's clock; anything else is no moment: said, and no picture)
        Object shotArg = hooks && getIntent().getExtras() != null ? getIntent().getExtras().get("shot_at") : null;
        if (shotArg != null && !(shotArg instanceof Integer)) Host.log("SHOT FAIL: shot_at is a moment in ms (--ei), not " + shotArg);
        Host.shotAt = shotArg instanceof Integer ? (Integer) shotArg : -1;
        // what another app shared into this one (ACTION_SEND or SEND_MULTIPLE: text, files), for the app to take
        Shares.take(getIntent());
        FrameLayout root = new FrameLayout(this);
        // over another app (OverActivity): nothing of the app's own ground, the app draws what is over it alone
        root.setBackgroundColor(over() ? Color.TRANSPARENT : night(getResources().getConfiguration()) ? Host.groundDark : Host.groundLight);
        MBView view = new MBView(this);
        mbView = view;
        folds = new Folds(this, view);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        root.addView(view, lp);
        // native views (NativeViews): over the MBView in the tree, so a page there takes its touches, under its
        // surface on the screen; laid out as the MBView is
        NativeViews.layer = new FrameLayout(this);
        layer = NativeViews.layer;
        root.addView(NativeViews.layer, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        // The view inside the system bars; the soft keyboard over its foot is told to it as it moves (Host.imeBottom:
        // the app lays out above it, its composer riding on the keyboard as Compose's imePadding does), the surface
        // itself not resized. Over another app (OverActivity) the view takes the whole window, under the bars too (as
        // still.fail's ShareActivity is edge to edge: its scrim from the screen's top, its sheet down to its foot), and
        // the bars are said to the app instead (src/hostapi/system.mbt `bars`).
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout());
            if (over()) {
                sayBars(bars);
                bars = Insets.NONE;
            } else if (edge) {
                // edge to edge, as Android's app is and iOS's: its pages run under the status bar, the navigation bar
                // and a cutout at a side (a phone turned sideways), each padded by what they cover (`bars`): what is
                // under them the app's own (a film's black to the screen's edges), not the window's ground beside it
                sayBars(bars);
                bars = Insets.NONE;
            }
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) view.getLayoutParams();
            if (p.leftMargin != bars.left || p.topMargin != bars.top
                    || p.rightMargin != bars.right || p.bottomMargin != bars.bottom) {
                p.setMargins(bars.left, bars.top, bars.right, bars.bottom);
                view.setLayoutParams(p);
                FrameLayout.LayoutParams q = (FrameLayout.LayoutParams) layer.getLayoutParams();
                q.setMargins(bars.left, bars.top, bars.right, bars.bottom);
                layer.setLayoutParams(q);
            }
            if (!imeMoving) keyboardAt(insets);
            // the window laid out again (opened, folded, split, turned): its size classes and the fold in it said
            folds.laidOut();
            // the keyboard put away by the person (its own key, Back, a swipe), not by the app: what was typed into
            // lets go of the focus, as the Android app's composer does; tapped again, it takes it and the keyboard
            // comes back (the app's own hiding comes after its focus went: Host.imeActive is off by then; a hiding seen
            // after the app asked for it again, the app's still under way: Host.imeAwaited)
            boolean shown = insets.isVisible(WindowInsets.Type.ime());
            if (imeShown && !shown && Host.imeActive && !Host.imeAwaited && mbView.hasWindowFocus()) {
                mbView.toGL(() -> Native.text(7, "", 0, 0));
            }
            // a keyboard the system brought back with no field of the app's wanting it: put away, unless a native
            // view's field (a page's) has the focus. (The app sent behind with the keyboard up, its field let go of as
            // the keyboard went; brought back, some systems put the keyboard up again over no field, and nothing the
            // app did let go of it: pengxiao 2026-10-25, scrolling a chat did not put it away)
            if (!imeShown && shown && !Host.imeActive && !Host.imeAwaited && root.findFocus() == mbView) {
                ((android.view.inputmethod.InputMethodManager) getSystemService(INPUT_METHOD_SERVICE))
                        .hideSoftInputFromWindow(mbView.getWindowToken(), 0);
            }
            imeShown = shown;
            Host.imeVisible = shown;
            if (shown) Host.imeAwaited = false;
            return WindowInsets.CONSUMED;
        });
        root.setWindowInsetsAnimationCallback(new WindowInsetsAnimation.Callback(
                WindowInsetsAnimation.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            @Override
            public void onPrepare(WindowInsetsAnimation a) {
                if ((a.getTypeMask() & WindowInsets.Type.ime()) != 0) imeMoving = true;
            }

            @Override
            public WindowInsets onProgress(WindowInsets insets, java.util.List<WindowInsetsAnimation> running) {
                for (WindowInsetsAnimation a : running) {
                    if ((a.getTypeMask() & WindowInsets.Type.ime()) != 0) {
                        keyboardAt(insets);
                        break;
                    }
                }
                return insets;
            }

            @Override
            public void onEnd(WindowInsetsAnimation a) {
                if ((a.getTypeMask() & WindowInsets.Type.ime()) == 0) return;
                imeMoving = false;
                WindowInsets now = root.getRootWindowInsets();
                if (now != null) keyboardAt(now);
                if (now != null && now.isVisible(WindowInsets.Type.ime())) Host.imeAwaited = false;
            }
        });
        setContentView(root);
        // edge to edge on every version, as Android 15 and later make it (an app targeting them): the view takes the
        // insets itself, the bars' and the keyboard's (above). Before it (Android 14, API 34) the decor fitted the
        // system's windows and, the soft input adjusting nothing, kept the keyboard's from the view: its height never
        // told, the composer under it (scripts/android-keyboard.sh on CI's API 34 emulator, run 39528189692)
        getWindow().setDecorFitsSystemWindows(false);
        // the window into a cutout at a side as well (a phone turned sideways), as Android 15 and later have it for an app
        // targeting them: before it the system kept that edge black, whatever the app had beside it
        if (edge) {
            android.view.WindowManager.LayoutParams a = getWindow().getAttributes();
            a.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            getWindow().setAttributes(a);
        }
        // the bars' icons as dark as the ground under them is light, the system's (the root's above) until the app says
        // its own (Host.setDark): dark icons on a dark ground till then, they showed a moment late as the app opened
        WindowInsetsController c = getWindow().getInsetsController();
        if (c != null) {
            int bars = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            c.setSystemBarsAppearance(night(getResources().getConfiguration()) ? 0 : bars, bars);
        }
        Host.activity = this;
        Host.view = view;
        Host.systemDark = night(getResources().getConfiguration());
        Host.fontScale = getResources().getConfiguration().fontScale;
        if (Host.script != null) Script.start(view);
        // started by a notification's tap (Notices): what it opens, for the app
        Notices.from(getIntent());
        // the default network as it changes, told to the app (src/hostapi/system.mbt), while an activity of the app lives
        NetworkWatch.hold(this);
    }

    /**
     * Since when the app has been off screen (elapsedRealtime: deep sleep counted); 0 while on it. The process's, not
     * an activity's: one closed with back and made again later is the same app coming back (as still.fail's
     * MainActivity's `hidden`). An app's push service reads it too (still.fail's Push.java: how long the app was away
     * as a push wakes its core).
     */
    static volatile long hiddenAt;

    /** The Wi-Fi multicast lock held while on screen, when the manifest asks for it (src/hostapi/system.mbt). */
    private android.net.wifi.WifiManager.MulticastLock multicast;

    @Override
    protected void onStart() {
        super.onStart();
        if (multicast == null && checkSelfPermission(android.Manifest.permission.CHANGE_WIFI_MULTICAST_STATE)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            android.net.wifi.WifiManager wifi = (android.net.wifi.WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
            if (wifi != null) {
                multicast = wifi.createMulticastLock("mbui-mdns");
                multicast.setReferenceCounted(false);
            }
        }
        if (multicast != null) multicast.acquire();
        Streams.behind(false);
        // the window's size classes and the device's fold, said to the app as they change (src/hostapi/system.mbt)
        folds.start();
        // back on screen after a while off it: said to the app (src/hostapi/system.mbt)
        if (hiddenAt != 0) {
            long away = Math.max(0, android.os.SystemClock.elapsedRealtime() - hiddenAt);
            hiddenAt = 0;
            Native.post("system", "{\"shown\":{\"away\":" + away + "}}");
        }
    }

    @Override
    protected void onStop() {
        // the drawing paused once the window is off the screen, not as it starts going: the system's animation of
        // the window going (into the launcher's icon, to the recent apps) moves what it last drew, as a View's
        mbView.onPause();
        // a remote screen's sound stops with its picture (Streams.behind)
        Streams.behind(true);
        folds.stop();
        if (multicast != null) multicast.release();
        if (hiddenAt == 0) hiddenAt = android.os.SystemClock.elapsedRealtime();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        NetworkWatch.release();
        super.onDestroy();
    }

    private boolean imeMoving;
    /** Whether the soft keyboard was shown, as the insets last said. */
    private boolean imeShown;
    /** The app lays itself out round the system bars (its manifest's dev.mbui.edge): its view under them. */
    private static boolean edge;

    /** This activity's own view and native views' layer: the host's (Host.view, NativeViews.layer) while it is resumed. */
    private MBView mbView;
    private FrameLayout layer;
    /** The window's size classes and the device's fold as the system says them (Folds). */
    private Folds folds;

    /** Whether this is the app over another app (OverActivity, a subclass: a share sheet over the app it came from). */
    boolean over() {
        return false;
    }

    /** What was last said of being over another app (src/hostapi/system.mbt `over`): null nothing yet. */
    private static Boolean saidOver;

    /** The bars last said to the app (over another app: sayBars), in pixels; null none yet. */
    private static Insets saidBars;

    /** The system bars over the view, said to the app as they change (src/hostapi/system.mbt `bars`): in points. */
    private void sayBars(Insets bars) {
        if (bars.equals(saidBars)) return;
        saidBars = bars;
        float d = mbView.density;
        Native.post("system", String.format(java.util.Locale.ROOT,
                "{\"bars\":{\"top\":%.2f,\"bottom\":%.2f,\"left\":%.2f,\"right\":%.2f}}",
                bars.top / d, bars.bottom / d, bars.left / d, bars.right / d));
    }

    /** How far the keyboard reaches over the view's foot (past the navigation bar it covers), told to the view. */
    private void keyboardAt(WindowInsets insets) {
        int ime = insets.getInsets(WindowInsets.Type.ime()).bottom;
        int bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout()).bottom;
        int over = Math.max(0, ime - bars);
        if (over != Host.imeBottom) {
            Host.imeBottom = over;
            // as it moves (onProgress, within the system's frame for it): drawn in this frame, as the keyboard is
            if (Host.view != null) {
                if (imeMoving) Host.view.frameNow();
                else Host.view.wantFrame();
            }
        }
    }

    /** Brought back (singleTask): by BrowserLogin once the browser has come back, or by its page's link. */
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        Notices.from(intent);
        Shares.take(intent);
        Host.log("activity onNewIntent " + (intent.getData() != null ? intent.getData().getScheme() + "://" + intent.getData().getHost() : "(in front again)"));
        Host.requestFrame();
    }

    // Back: while the app has a page to go back to (Host.backEnabled), the system's back is the app's, its
    // predictive back gesture followed as it goes (Android 14 on: OnBackAnimationCallback; 13: back only once
    // done); otherwise the system's own (leaving the app). Told to MoonBit on the GL thread by the next frame (MBView.back).
    private boolean backOn;
    private Object backCallback;

    private void back(int kind, float x, float progress, int edge) {
        MBView v = Host.view;
        if (v == null) return;
        v.back(kind, x / v.density, progress, edge);
    }

    void setBackEnabled(boolean on) {
        if (on == backOn) return;
        backOn = on;
        if (Build.VERSION.SDK_INT < 33) return;  // onBackPressed asks backOn
        OnBackInvokedDispatcher dispatcher = getOnBackInvokedDispatcher();
        if (on) {
            if (Build.VERSION.SDK_INT >= 34) {
                backCallback = new OnBackAnimationCallback() {
                    @Override public void onBackStarted(BackEvent e) {
                        back(0, e.getTouchX(), e.getProgress(), e.getSwipeEdge() == BackEvent.EDGE_RIGHT ? 1 : 0);
                    }
                    @Override public void onBackProgressed(BackEvent e) {
                        back(1, e.getTouchX(), e.getProgress(), e.getSwipeEdge() == BackEvent.EDGE_RIGHT ? 1 : 0);
                    }
                    @Override public void onBackInvoked() { back(2, 0, 1, 0); }
                    @Override public void onBackCancelled() { back(3, 0, 0, 0); }
                };
            } else {
                backCallback = (OnBackInvokedCallback) () -> back(2, 0, 1, 0);
            }
            dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                    (OnBackInvokedCallback) backCallback);
        } else if (backCallback != null) {
            dispatcher.unregisterOnBackInvokedCallback((OnBackInvokedCallback) backCallback);
            backCallback = null;
        }
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (Host.backWanted) back(2, 0, 1, 0);
        else super.onBackPressed();
    }

    /** A picker's answer (Picks: the photo picker, the documents UI, the camera). */
    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int request, int result, Intent data) {
        if (!Picks.answered(request, result, data) && !Keeps.answered(request, result, data)) super.onActivityResult(request, result, data);
    }

    /** The system's answer to POST_NOTIFICATIONS (Notices: asked as notifications are turned on, or once at first). */
    @Override
    public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        if (request == Gallery.ASK) {
            Gallery.answered();
            return;
        }
        if (request == Notices.ASK) {
            Notices.answered(results.length > 0 && results[0] == android.content.pm.PackageManager.PERMISSION_GRANTED);
            return;
        }
        super.onRequestPermissionsResult(request, permissions, results);
    }

    /** Whether a configuration is in night mode (the system's dark theme). */
    private static boolean night(android.content.res.Configuration c) {
        return (c.uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    }

    /** The system's theme changed (configChanges has uiMode: the activity is not made again): the app asks it next frame. */
    @Override
    public void onConfigurationChanged(android.content.res.Configuration c) {
        super.onConfigurationChanged(c);
        // a fold opened or closed: a phone's screen upright only, a tablet's as turned (Host.upright)
        Host.holdUpright(this);
        // the system's size of words changed (configChanges has fontScale): the next frame draws words at it
        if (c.fontScale != Host.fontScale) {
            Host.fontScale = c.fontScale;
            Host.requestFrame();
        }
        boolean dark = night(c);
        if (dark != Host.systemDark) {
            Host.systemDark = dark;
            Host.requestFrame();
        }
        // (configChanges has screenSize, smallestScreenSize and screenLayout: an opened or folded phone's window too)
        folds.laidOut();
    }

    @Override
    protected void onPause() {
        super.onPause();
        // the core hears the app left the front (its drawing goes on until the window is off the screen: onStop)
        Host.resumed = false;
        Host.tellAppState();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // the host's this activity's again (the app over another app, OverActivity, came and went meanwhile)
        Host.activity = this;
        Host.view = mbView;
        NativeViews.moveTo(layer);
        // (the streams' layers under this activity's surface, where it has one)
        StreamLayer.parentFrom(mbView);
        Native.overOther(over());
        mbView.onResume();
        // back as the app has it now, whatever this activity was told before (Host.backWanted)
        setBackEnabled(Host.backWanted);
        Host.resumed = true;
        Host.tellAppState();
        // a newer build asked for while the person was away giving the leave to install it (Updates.resumed)
        Updates.resumed();
        // whether it is over another app, said to the app as it changes (src/hostapi/system.mbt `over`)
        if (saidOver == null || saidOver != over()) {
            saidOver = over();
            Native.post("system", "{\"over\":" + over() + "}");
        }
    }

    @Override
    public void onWindowFocusChanged(boolean has) {
        super.onWindowFocusChanged(has);
        Host.focused = has;
        if (has) NativeViews.focused();
        Host.windowFocused(has);
        Host.tellAppState();
    }

    /** A debug build, or any build on the emulator (its hardware ranchu, goldfish before it). */
    private boolean testHooks() {
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) return true;
        return Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish");
    }
}
