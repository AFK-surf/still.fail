package dev.mbui;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

/**
 * The system's browser session on Android (an app's engine's web_auth, mbui/core's core_client.h; iOS's
 * ASWebAuthenticationSession): the page in a Custom Tab on the app's task, and the browser sent back to the app's own
 * scheme, its package's (&lt;package&gt;://auth/…, MainActivity's intent filter), which the system hands to the app
 * as an intent. Unlike a loopback listener ({@link BrowserLogin}), nothing has to keep running while the person is in
 * the browser: a vendor's freezer (ColorOS's freezes a backgrounded app within seconds, its foreground service and
 * sockets with it) cannot leave the browser's way back unanswered, as the system thaws the app to hand it the intent.
 * Bringing the app's singleTask activity back closes the tab above it. The person back in the app without it (the
 * tab closed) is the session given up ("cancelled"), as iOS says it.
 */
final class WebAuth {
    /** A session's page is out, its end not told yet. */
    private static boolean waiting;
    /** The app has left the front since (the tab came over it): its coming back without the way back is giving up. */
    private static boolean left;

    private WebAuth() {}

    /** The scheme the browser comes back on: the app's package (unique to each build: stable, beta, dev, monoid). */
    static String scheme() {
        Activity a = Host.activity;
        return a != null ? a.getPackageName() : "";
    }

    /** Opens `url` in a Custom Tab (the system's browser where none takes one): false when nothing took it. */
    static boolean open(String url) {
        Host.main.post(() -> {
            // (one under way was given up for this one by the host: android_host.c mb_host_web_auth)
            waiting = true;
            left = false;
            if (!BrowserLogin.openTab(url)) {
                waiting = false;
                Native.webAuthBack(null, "no browser here to open the page");
            }
        });
        return true;
    }

    /** MainActivity paused: the tab over it, or the person elsewhere. */
    static void paused() {
        if (waiting) left = true;
    }

    /** An intent the app was brought back or started with: true when it is the browser coming back on the scheme. */
    static boolean took(Intent intent) {
        Uri data = intent != null ? intent.getData() : null;
        String own = scheme();
        if (data == null || own.isEmpty() || !own.equals(data.getScheme()) || !"auth".equals(data.getHost())) return false;
        if (!waiting) {
            // (the process started anew meanwhile: nobody waits for it; signing in again starts another)
            Host.log("web auth: came back with none waiting");
            return true;
        }
        waiting = false;
        Host.log("web auth: back from the browser");
        Native.webAuthBack(data.toString(), null);
        Host.requestFrame();
        return true;
    }

    /** MainActivity resumed: back in the app without the browser having come back is the session given up. */
    static void resumed() {
        if (!waiting || !left) return;
        waiting = false;
        Host.log("web auth: back in the app without signing in");
        Native.webAuthBack(null, "cancelled");
        Host.requestFrame();
    }
}
