package dev.mbui;

import android.app.Application;

/**
 * still.fail mbui's process, before its activity (mbui's MainActivity, the host's): what still.fail's Android app sets
 * going in its MainActivity.onCreate. A crash's exception kept (Crashes), the native heap watched (MemoryWatch), the
 * bar's switches timed from the finger lifted (BarTiming).
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
    }
}
