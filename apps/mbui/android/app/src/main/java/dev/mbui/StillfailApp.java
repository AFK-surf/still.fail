package dev.mbui;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

/**
 * still.fail mbui's process, before its activity (mbui's MainActivity, the host's): what still.fail's Android app sets
 * going in its MainActivity.onCreate. A crash's exception kept (Crashes), the native heap watched (MemoryWatch), the
 * bar's switches timed from the finger lifted (BarTiming), 共享调试's native calls put (AdbShare), the push token asked
 * for (Push), and the core started as the app's activity is made (coreAhead).
 */
public final class StillfailApp extends Application {
    static StillfailApp app;

    @Override
    public void onCreate() {
        super.onCreate();
        app = this;
        Crashes.install(this);
        MemoryWatch.start(this);
        BarTiming.start(this);
        // 共享调试's native calls for the app (adb.phone, adb.open, adb.switch, adb.start: AdbShare.java)
        AdbShare.install(this);
        // FCM's token for the app to register as the core says (Push.java; none where this package has no Firebase app)
        Push.start(this);
        coreAhead();
    }

    private static boolean coreStarted;

    /**
     * The core started on a thread of its own as the app's first activity is made (its environment set: MainActivity's
     * onCreate), not as the app's MoonBit starts on the drawing thread once the window's surface is made: its engine,
     * its script read out of the APK, its database opened and its first answers ready while the system lays the window
     * out and the drawing is set up, none of it on the drawing thread. The app takes it as its own as it starts (as one
     * a push started: android_core.c mb_core_start), the same files, still.fail cloud and channel it would have given.
     * Not in a run to a declared moment (Host.shotAt: the core on the app's clock from its start), nor in a process
     * started for anything but an activity (a push's starts its own as it needs one).
     */
    private void coreAhead() {
        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            // (after its onCreate: the environment it sets is there; onActivityCreated is told inside its super.onCreate)
            @Override
            public void onActivityPostCreated(Activity a, Bundle saved) {
                if (coreStarted || !(a instanceof MainActivity) || Host.shotAt >= 0) return;
                coreStarted = true;
                String cloud = Push.cloud(a);
                boolean beta = Push.beta(a);
                new Thread(() -> {
                    long t = android.os.SystemClock.uptimeMillis();
                    boolean on = CoreHost.startAlone(cloud, beta);
                    Host.log("core ahead: " + (on ? "started" : "not started") + " in "
                            + (android.os.SystemClock.uptimeMillis() - t) + " ms, "
                            + (t - android.os.Process.getStartUptimeMillis()) + " ms after the process started");
                }, "core-ahead").start();
            }

            @Override public void onActivityCreated(Activity a, Bundle saved) {}
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityResumed(Activity a) {}
            @Override public void onActivityPaused(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle out) {}
            @Override public void onActivityDestroyed(Activity a) {}
        });
    }
}
