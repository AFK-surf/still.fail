package dev.mbui;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Bundle;
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
