package dev.mbui;

import android.app.Application;

/**
 * still.fail mbui's process, before its activity (mbui's MainActivity, the host's): what still.fail's Android app sets
 * going in its MainActivity.onCreate. A crash's exception kept (Crashes), the native heap watched (MemoryWatch), the
 * bar's switches timed from the finger lifted (BarTiming), 共享调试's native calls put (AdbShare), the push token asked
 * for (Push).
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
    }
}
