package dev.mbui;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.Application;
import android.os.Bundle;

/**
 * still.fail mbui's process, before its activity (mbui's MainActivity, the host's): what still.fail's Android app sets
 * going in its MainActivity.onCreate. A crash's exception kept (Crashes), the core started where the process is
 * started for the app's activity (coreAhead), the native heap watched (MemoryWatch), the bar's switches timed from the
 * finger lifted (BarTiming), 共享调试's native calls put (AdbShare), the push token asked for (Push); in the keyboard's
 * process (Keyboard.java) only the crash kept.
 */
public final class StillfailApp extends Application {
    static StillfailApp app;

    @Override
    public void onCreate() {
        super.onCreate();
        app = this;
        Crashes.install(this);
        // the keyboard's own process (Keyboard, the manifest's android:process): the keyboard alone, none of the app's
        if (getProcessName().endsWith(":keyboard")) return;
        coreAhead();
        MemoryWatch.start(this);
        BarTiming.start(this);
        // 共享调试's native calls for the app (adb.phone, adb.open, adb.switch, adb.start: AdbShare.java)
        AdbShare.install(this);
        // FCM's token for the app to register as the core says (Push.java; none where this package has no Firebase app)
        Push.start(this);
    }

    private static boolean coreStarted;

    /**
     * The core started on a thread of its own as the process starts for the app's activity, not as the app's MoonBit
     * starts on the drawing thread once the window's surface is made: its engine, its script read out of the APK, its
     * database opened and its first answers ready while the system makes the activity and lays the window out, none of
     * it on the drawing thread. The app takes it as its own as it starts (as one a push started: android_core.c
     * mb_core_start), unless the run gives the app another still.fail cloud or channel than the build's (its manifest's
     * dev.mbui.env, which this one was given: the test hooks' env), which has the app start its own. A process started
     * for anything else (a push, a service, the accessibility service) starts one as its activity is made, if it is.
     */
    private void coreAhead() {
        ActivityManager.RunningAppProcessInfo me = new ActivityManager.RunningAppProcessInfo();
        ActivityManager.getMyMemoryState(me);
        Host.log("process started at importance " + me.importance);
        if (me.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) startAhead(this);
        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            // (after its onCreate: the environment it sets is there; onActivityCreated is told inside its super.onCreate)
            @Override
            public void onActivityPostCreated(Activity a, Bundle saved) {
                if (a instanceof MainActivity) startAhead(a);
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

    /** (also for the chats' grants the phone was lent for as the process went: AdbShare.install) */
    static void startAhead(android.content.Context c) {
        if (coreStarted) return;
        coreStarted = true;
        String cloud = Push.cloud(c);
        boolean beta = Push.beta(c);
        new Thread(() -> {
            long t = android.os.SystemClock.uptimeMillis();
            boolean on;
            try {
                on = CoreHost.startAlone(cloud, beta);
            } catch (UnsatisfiedLinkError e) {
                // (a build with no core of its own: sffix's, the made-up chats the measuring runs draw)
                Host.log("core ahead: none in this build: " + e.getMessage());
                return;
            }
            Host.log("core ahead: " + (on ? "started" : "not started") + " in "
                    + (android.os.SystemClock.uptimeMillis() - t) + " ms, "
                    + (t - android.os.Process.getStartUptimeMillis()) + " ms after the process started");
        }, "core-ahead").start();
    }
}
