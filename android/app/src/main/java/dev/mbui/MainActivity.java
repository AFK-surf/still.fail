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
import android.view.WindowInsetsController;
import android.widget.FrameLayout;

/** Hosts one MBView inside the system bars and above the keyboard. */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        Host.log("activity onCreate " + (saved != null ? "(restored)" : ""));
        Host.activity = this;
        // `--es env K=V;K2=V2`: environment variables for the app's MoonBit (as a desktop run has them: the core
        // demo's MBUI_AUTH_BEGIN, MBUI_CORE_DUMP…), set before it starts.
        String env = getIntent().getStringExtra("env");
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
        Host.script = getIntent().getStringExtra("script");
        Host.bench = getIntent().getIntExtra("bench", 0);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(245, 245, 247));
        MBView view = new MBView(this);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        root.addView(view, lp);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) view.getLayoutParams();
            if (p.leftMargin != bars.left || p.topMargin != bars.top
                    || p.rightMargin != bars.right || p.bottomMargin != bars.bottom) {
                p.setMargins(bars.left, bars.top, bars.right, bars.bottom);
                view.setLayoutParams(p);
            }
            return WindowInsets.CONSUMED;
        });
        setContentView(root);
        WindowInsetsController c = getWindow().getInsetsController();
        if (c != null) {
            c.setSystemBarsAppearance(WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        }
        Host.activity = this;
        Host.view = view;
        if (Host.script != null) Script.start(view);
    }

    /** Brought back (singleTask): by BrowserLogin once the browser has come back, or by its page's link. */
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        Host.log("activity onNewIntent " + (intent.getData() != null ? intent.getData().getScheme() + "://" + intent.getData().getHost() : "(in front again)"));
        Host.requestFrame();
    }

    // Back: while the app has a page to go back to (Host.backEnabled), the system's back is the app's, its
    // predictive back gesture followed as it goes (Android 14 on: OnBackAnimationCallback; 13: back only once
    // done); otherwise the system's own (leaving the app). Told to MoonBit on the GL thread (Native.back).
    private boolean backOn;
    private Object backCallback;

    private void back(int kind, float x, float progress, int edge) {
        MBView v = Host.view;
        if (v == null) return;
        float d = v.density;
        v.toGL(() -> Native.back(kind, x / d, progress, edge));
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
        if (backOn) back(2, 0, 1, 0);
        else super.onBackPressed();
    }

    @Override
    protected void onPause() {
        super.onPause();
        Host.view.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        Host.view.onResume();
    }
}
