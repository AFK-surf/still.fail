package dev.mbui;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * A sign-in in the browser that comes back to this app (mbui/hostapi {@code browser_login}, src/hostapi/browser_login.mbt),
 * Android's twin of src/host/apple_browser_login.m, on the {@link Loopback} listener: the way command-line tools sign
 * in (OAuth's loopback redirect, RFC 8252 §7.3). Listen on 127.0.0.1 at a port the system picks, let the app make its
 * login page with http://127.0.0.1:&lt;port&gt;&lt;path&gt; as where to come back, open it in a Custom Tab (the browser's,
 * through the Custom Tabs protocol's own extras: no androidx needed; a browser without them opens a plain view), take
 * the one GET that comes back to &lt;path&gt; under that host name, answer it, stop listening, and bring the app back in
 * front of the browser. Nothing here knows whose sign-in it is: the app checks what came back (its state) and
 * exchanges it. The app polls it each frame (one is asked for when the browser comes back). Called from the GL thread.
 */
final class BrowserLogin {
    private static final class Login {
        final String path;
        /** Where the browser is sent on to once it has come back (the app's page saying it is done): "", this one's. */
        final String done;
        volatile int lid, port;
        /** Where the browser came back to (http://127.0.0.1:&lt;port&gt;&lt;path&gt;?&lt;query&gt;), once it has. */
        volatile String back;

        Login(String path, String done) {
            this.path = path;
            this.done = done;
        }
    }

    private static final Map<Integer, Login> logins = new ConcurrentHashMap<>();
    private static final AtomicInteger next = new AtomicInteger(1);

    private BrowserLogin() {}

    /**
     * Listens for the browser coming back to {@code path}, to be sent on to {@code done} ("": shown this host's page):
     * the sign-in's id, 0 when no port could be had.
     */
    static int start(String path, String done) {
        int bid = next.getAndIncrement();
        Login login = new Login(path, done);
        logins.put(bid, login);
        try {
            // Set before any request can come: one comes only once the browser has the page, which needs the port.
            login.lid = Loopback.open("127.0.0.1", 0, r -> took(login, r));
            login.port = Loopback.port(login.lid);
        } catch (Exception e) {
            Host.log("browser login: cannot listen: " + e);
            logins.remove(bid);
            return 0;
        }
        Host.log("browser login: listening on 127.0.0.1:" + login.port + " for " + path);
        return bid;
    }

    static int port(int bid) {
        Login l = logins.get(bid);
        return l != null ? l.port : 0;
    }

    /** Opens the login page in the browser: 0 when there is none to open it. */
    static int open(int bid, String url) {
        Activity a = Host.activity;
        if (a == null) return 0;
        Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        view.addCategory(Intent.CATEGORY_BROWSABLE);
        if (a.getPackageManager().queryIntentActivities(view, 0).isEmpty()) {
            Host.log("browser login: no browser here to open the page");
            return 0;
        }
        // A Custom Tab: the extras CustomTabsIntent puts (androidx.browser), a session of none, the page's title shown.
        Bundle session = new Bundle();
        session.putBinder("android.support.customtabs.extra.SESSION", null);
        view.putExtras(session);
        view.putExtra("android.support.customtabs.extra.TITLE_VISIBILITY", 1);
        Host.main.post(() -> {
            try {
                // From the activity, without NEW_TASK: the tab sits on this app's task, so bringing the app back
                // (singleTask) closes it.
                a.startActivity(view);
            } catch (ActivityNotFoundException e) {
                Host.log("browser login: the browser did not open: " + e);
            }
        });
        return 1;
    }

    /**
     * A page in a Custom Tab over the app (@hostapi.open_tab: a login's page, as still.fail's LoginCards.kt openLoginPage),
     * or in the system's browser where none takes a tab; false when nothing takes it at all.
     */
    static boolean openTab(String url) {
        Activity a = Host.activity;
        if (a == null || url == null || url.isEmpty()) return false;
        Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        view.addCategory(Intent.CATEGORY_BROWSABLE);
        if (a.getPackageManager().queryIntentActivities(view, 0).isEmpty()) return Host.openUrl(url);
        Bundle session = new Bundle();
        session.putBinder("android.support.customtabs.extra.SESSION", null);
        view.putExtras(session);
        view.putExtra("android.support.customtabs.extra.TITLE_VISIBILITY", 1);
        Host.main.post(() -> {
            try {
                a.startActivity(view);
                Host.log("open-tab: " + url);
            } catch (ActivityNotFoundException e) {
                Host.openUrl(url);
            }
        });
        return true;
    }

    static String back(int bid) {
        Login l = logins.get(bid);
        String b = l != null ? l.back : null;
        return b != null ? b : "";
    }

    static void end(int bid) {
        Login l = logins.remove(bid);
        if (l != null) Loopback.close(l.lid);
    }

    private static byte[] page(String title, String text, String link) {
        return ("<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>" + title
                + "</title><body style=\"font:16px system-ui,sans-serif;margin:3em 2em;color:#1c1c1e\"><p>" + text + "</p>"
                + (link != null ? "<p><a href=\"" + link + "\" style=\"color:#0a84ff\">回到 app · Back to the app</a></p>" : "")
                + "</body>").getBytes(StandardCharsets.UTF_8);
    }

    /** On a listener's thread: the request that came, answered at once (only the one this sign-in waits for is taken). */
    private static void took(Login login, Loopback.Asked r) {
        if (r == null) return;  // closed
        String path = r.path;
        int q = path.indexOf('?');
        String bare = q < 0 ? path : path.substring(0, q);
        String host = r.header("host");
        // Only the browser coming back to this sign-in: its address (a page elsewhere naming 127.0.0.1 by another
        // name, DNS rebinding, is not), its path, a GET.
        boolean ours = (host.equals("127.0.0.1:" + login.port) || host.equals("localhost:" + login.port))
                && r.method.equals("GET") && bare.equals(login.path);
        Activity a = Host.activity;
        String pkg = a != null ? a.getPackageName() : "";
        // The way back, should the app not come forward by itself (MainActivity's intent filter for <package>://back).
        String link = a != null ? "intent://back#Intent;scheme=" + pkg + ";package=" + pkg + ";end" : null;
        if (ours && !login.done.isEmpty()) {
            // On to the app's page saying it is done (in its look, the browser's language), told the app's package for
            // its own way back.
            String to = login.done + (login.done.indexOf('?') < 0 ? "?" : "&") + "app=" + Uri.encode(pkg);
            Loopback.respond(login.lid, r.request, 302,
                    Arrays.asList(new String[] {"Location", to}, new String[] {"Cache-Control", "no-store"}), new byte[0]);
        } else {
            List<String[]> headers = Arrays.asList(new String[] {"Content-Type", "text/html; charset=utf-8"},
                    new String[] {"Cache-Control", "no-store"});
            Loopback.respond(login.lid, r.request, ours ? 200 : 404, headers,
                    ours ? page("Signed in", "已回到 app，可以关掉这个页面 · Back in the app: you can close this page", link)
                         : page("Not found", "这不是这次登录的地址 · Not this sign-in", null));
        }
        Host.log("browser login: " + r.method + " " + bare + " (Host " + host + ") " + (ours ? "taken" : "refused"));
        if (!ours) return;
        Loopback.close(login.lid);  // after the answer: nothing else is taken
        if (login.back == null) login.back = "http://127.0.0.1:" + login.port + path;
        Host.requestFrame();
        frontAgain();
    }

    /**
     * The app in front again, over the browser, as still.fail's app comes back (its stillfail://auth/callback brings
     * its singleTask activity back, which closes the Custom Tab above it): here the app asks for itself. Android lets it
     * while the tab is on the app's own task; when it does not, the page's link does it.
     */
    private static void frontAgain() {
        Host.main.post(() -> {
            Activity a = Host.activity;
            if (a == null) return;
            try {
                a.startActivity(new Intent(a, MainActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
                Host.log("browser login: back in the app");
            } catch (RuntimeException e) {
                Host.log("browser login: the app could not come forward: " + e);
            }
        });
    }
}
