package dev.mbui;

/**
 * What the MoonBit app tells still.fail's own host (src/stillfail/reports.mbt, through src/host/android_reports.c), on
 * the UI's (GL) thread: the account signed in, the core failing, the bar's switches and the topics their pages subscribe.
 */
final class Reports {
    private Reports() {}

    /** {@code what} with its words ({@code a}, {@code b}) and numbers ({@code n}, {@code m}); what it answers. */
    static int tell(String what, String a, String b, int n, int m) {
        StillfailApp app = StillfailApp.app;
        if (app == null) return 0;
        long now = System.nanoTime();
        switch (what) {
            // whether this host takes them
            case "hello":
                return 1;
            // whether usage statistics and error reports go out from this device: 1 yes, 0 turned off, -1 a build
            // without PostHog's key, which sends nothing (the settings show no row then)
            case "reporting":
                return !Crashes.hasKey() ? -1 : Crashes.reporting(app) ? 1 : 0;
            // turned on (n 1) or off (0) in the settings
            case "set_reporting":
                Crashes.setReporting(app, n != 0);
                return 0;
            // the first account signed in (its `sub`): what crashed before this start goes as it (Crashes.report)
            case "signed_in":
                Crashes.report(app, a);
                return 0;
            // the core failed, its reason (Crashes.coreFailed: StillFailCore.onFailed's)
            case "core_failed":
                Crashes.coreFailed(app, a);
                return 0;
            // a place's page put on the stack: the place left ("" none), the place
            case "placed":
                BarTiming.placed(a, b, now);
                return 0;
            // the first frame's build that had it, over
            case "built":
                BarTiming.built(a, now);
                return 0;
            // a topic subscribed (its name, its subscription's id): 1 when a switch times it
            case "followed":
                return BarTiming.followed(n, a, now) ? 1 : 0;
            // its first message taken: its id, its value's size in bytes (-1: an error)
            case "decoded":
                BarTiming.decoded(n, m, now);
                return 0;
            default:
                return 0;
        }
    }
}
