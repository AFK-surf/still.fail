package dev.mbui;

import android.content.Context;
import android.os.SystemClock;

import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import org.json.JSONObject;

import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * Pushes, as still.fail's Android app has them (its Push.kt): Firebase Cloud Messaging, set up by hand from the app's
 * resources (res/values/push.xml: apps/android/firebase.properties' values) rather than google-services.json, for the
 * Firebase app of the package the app is built as (fail.still.android.beta's; none registered for the others, whose
 * pushes stay off and only local notices are shown). The device's token goes to mbui's host (dev.mbui.Notices.token),
 * which the app registers as the core's {@code notify} says (src/sfapp/notices.mbt push_sync: {@code push.register},
 * a new token registered again).
 */
final class Push {
    private Push() {}

    /** The Firebase app of this package (as firebase.properties names them): "" where none is registered. */
    private static String appId(Context c) {
        return "fail.still.android.beta".equals(c.getPackageName()) ? c.getString(R.string.fcm_beta_app_id) : "";
    }

    /** Firebase for this process, once; false when this package has no Firebase app. */
    static synchronized boolean init(Context context) {
        Context c = context.getApplicationContext();
        String app = appId(c);
        if (app.isEmpty()) return false;
        if (FirebaseApp.getApps(c).isEmpty()) {
            FirebaseOptions options = new FirebaseOptions.Builder()
                    .setProjectId(c.getString(R.string.fcm_project_id))
                    .setApplicationId(app)
                    .setApiKey(c.getString(R.string.fcm_api_key))
                    .setGcmSenderId(c.getString(R.string.fcm_sender_id))
                    .build();
            FirebaseApp.initializeApp(c, options);
        }
        return true;
    }

    /**
     * The device's token, asked for as the app starts (StillfailApp): given to mbui's host once FCM has it. Unlike the
     * Kotlin app (Push.sync asks only when the core wants pushes), the token is made whether or not they are on: the
     * app's MoonBit side reads it ({@code push_token}) and registers it only when the core's {@code notify} says so.
     */
    static void start(Context context) {
        if (!init(context)) return;
        FirebaseMessaging.getInstance().getToken().addOnCompleteListener(t -> {
            if (t.isSuccessful() && t.getResult() != null) {
                Host.log("push: a token");
                Notices.token(t.getResult());
            } else {
                // (what FCM says is the outermost; why is a cause or two in)
                for (Throwable e = t.getException(); e != null; e = e.getCause()) Host.log("push: no token: " + e);
            }
        });
    }

    /** How long a push keeps the app running to bring what it is about (FCM gives a high-priority message some 10 s). */
    private static final long BRING_MS = 8_000;
    /** How long the core is given to say whether a push is shown (PushService.shown). */
    private static final long SHOWN_MS = 5_000;
    /** How long a new token is given to be registered (PushService.onNewToken). */
    private static final long REGISTER_MS = 30_000;
    /** When a push last woke the core while the app was off screen (elapsedRealtime; 0 none). */
    private static long woke;

    /** The core's answer to {@code call} (AdbCore: the app's client, ids of its own), null if it failed or took past `ms`. */
    private static Object ask(String call, JSONObject params, long ms) {
        if (ms <= 0) return null;
        CountDownLatch done = new CountDownLatch(1);
        Object[] got = {null};
        AdbCore.call(call, params, new AdbCore.Answer() {
            @Override
            public void ok(Object value) {
                got[0] = value == null ? JSONObject.NULL : value;
                done.countDown();
            }

            @Override
            public void error(String why) {
                Host.log("push: " + call + ": " + why);
                done.countDown();
            }
        });
        try {
            done.await(ms, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return got[0];
    }

    /**
     * What the app's environment says of `key`, as its activity sets it (MainActivity: the process's own, else the
     * defaults its manifest's dev.mbui.env says): "" none. A push's process may have no activity yet.
     */
    private static String env(Context c, String key) {
        String v = System.getenv(key);
        if (v != null && !v.isEmpty()) return v;
        try {
            android.os.Bundle meta = c.getPackageManager()
                    .getApplicationInfo(c.getPackageName(), android.content.pm.PackageManager.GET_META_DATA).metaData;
            String defaults = meta == null ? null : meta.getString("dev.mbui.env");
            if (defaults != null) for (String kv : defaults.split(";")) {
                int at = kv.indexOf('=');
                if (at > 0 && kv.substring(0, at).equals(key)) return kv.substring(at + 1);
            }
        } catch (Exception e) {
            Host.log("push: " + e);
        }
        return "";
    }

    /** still.fail cloud, as the app's core is given it (sfcore start: MBUI_CLOUD, else still.fail's own). */
    private static String cloud(Context c) {
        String v = env(c, "MBUI_CLOUD");
        return v.isEmpty() ? "https://app.still.fail" : v;
    }

    /** Whether the app's core is a beta's (sfcore start: MBUI_BETA=1, the beta app's build). */
    private static boolean beta(Context c) {
        return env(c, "MBUI_BETA").equals("1");
    }

    /**
     * FCM's side (Push.kt PushService), on its own thread, with the core: the app's where it runs, else one started for
     * it (StillFailCore.start there; CoreHost.startAlone), stopped once done unless the app has taken it meanwhile. A
     * new token is registered; a push is shown unless the core says not ({@code notice.pushed}: notifications off, a
     * page in view, another workspace's, its kind off), then what it is about brought onto the device
     * ({@code notice.bring}) while FCM lets the app run.
     */
    public static final class Service extends FirebaseMessagingService {
        @Override
        public void onCreate() {
            Crashes.install(getApplicationContext());
            init(this);
            super.onCreate();
        }

        @Override
        public void onNewToken(String token) {
            // (for the app as it next looks; registered here too, as the app's frames stop while it is behind: with
            // notifications off the core takes none)
            Notices.token(token);
            boolean alone = !CoreHost.running();
            if (!CoreHost.startAlone(cloud(this), beta(this))) return;
            try {
                JSONObject p = new JSONObject().put("kind", "fcm").put("token", token);
                ask("push.register", p, REGISTER_MS);
            } catch (Exception e) {
                Host.log("push: " + e);
            } finally {
                if (alone) CoreHost.stopAlone();
            }
        }

        @Override
        public void onMessageReceived(RemoteMessage message) {
            Map<String, String> data = message.getData();
            String tag = data.get("tag"), url = data.get("url");
            if (!"notice".equals(data.get("type")) || tag == null || url == null) return;
            boolean alone = !CoreHost.running();
            boolean core = CoreHost.startAlone(cloud(this), beta(this));
            try {
                boolean show = shown(core, data.get("workspace"), data.get("kind"));
                Host.log("push: " + tag + (show ? " shown" : " not shown") + (alone ? " (a core of its own)" : ""));
                if (!show) return;
                String seq = data.get("seq");
                String title = data.get("title");
                String body = data.get("body");
                // (the channel named as the app names it, its words only Chinese so far: sfapp strings.mbt)
                Notices.show(this, "消息", tag, title == null ? "" : title, body == null ? "" : body,
                        url + "\n" + (seq == null ? "" : seq));
                if (core) bring(data.get("workspace"), data.get("station"), data.get("session"), seq);
            } finally {
                if (alone) CoreHost.stopAlone();
            }
        }

        /** The core's say, or (it not answering) shown unless the app is in front, which shows its own. */
        private static boolean shown(boolean core, String workspace, String kind) {
            if (core) {
                JSONObject p = new JSONObject();
                try {
                    if (workspace != null) p.put("workspace", workspace);
                    if (kind != null) p.put("kind", kind);
                } catch (Exception ignored) {
                }
                Object a = ask("notice.pushed", p, SHOWN_MS);
                if (a instanceof JSONObject && ((JSONObject) a).opt("show") instanceof Boolean) return ((JSONObject) a).optBoolean("show");
            }
            Host.log("push: the core did not say; shown unless the app is in front");
            return !Host.resumed;
        }

        /**
         * What the push is about, onto the device (`notice.bring`): tapped, its chat opens on it instead of waiting for
         * the station to be reached again. The app off screen was likely frozen, its connections gone with nothing
         * said: the core is told how long it was away first (`client.wake`, as when the app comes back: MainActivity's
         * hiddenAt), since it went or since the push before woke it. Back on screen, it is still as long away as it was.
         */
        private static void bring(String workspace, String station, String session, String seq) {
            if (workspace == null || station == null || session == null) return;
            long start = SystemClock.elapsedRealtime();
            try {
                long hidden = MainActivity.hiddenAt;
                if (hidden != 0) {
                    long since = Math.max(hidden, woke != 0 ? woke : hidden);
                    woke = start;
                    ask("client.wake", new JSONObject().put("away", Math.max(0, start - since)), BRING_MS);
                }
                JSONObject b = new JSONObject().put("station", workspace + "/" + station).put("session", session);
                if (seq != null) {
                    try {
                        b.put("seq", Long.parseLong(seq));
                    } catch (NumberFormatException ignored) {
                    }
                }
                ask("notice.bring", b, BRING_MS - (SystemClock.elapsedRealtime() - start));
            } catch (Exception e) {
                Host.log("push: " + e);
            }
        }
    }
}
