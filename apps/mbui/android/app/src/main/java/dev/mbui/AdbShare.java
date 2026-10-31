package dev.mbui;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.RemoteInput;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

/**
 * This phone's adb, lent to a station's agents (docs/adb-share.md; still.fail's Android app's AdbShare.kt, as it is):
 * Wireless debugging's ports found on the phone (DNS-SD: AdbPorts) and given to the core (`adb.share`), which offers
 * them to the station and carries what its agents' adb sends. A foreground service (AdbShareService) holds the app up
 * meanwhile and says so, with 停止. While the pairing dialog is open its code is read off it (AdbCodeReader, where the
 * person turned that on), else a second notification pops up over it with a field for the code.
 *
 * The app's 共享调试 page (src/sfapp/settings/station_parts.mbt adb_page) asks through mbui's native calls
 * (@ui.native_call; dev.mbui.Natives), put here as the app starts (StillfailApp):
 *   adb.phone    what the phone has for it: {supported, developer, wireless, wifi, canSwitch, reads}; said again
 *                by itself on "native:adb.phone" as Wireless debugging is switched and as the app comes back
 *   adb.open     {what: "wireless", beside} Developer options at Wireless debugging (beside the app, split), or
 *                {what: "reader"} Accessibility at AdbCodeReader
 *   adb.switch   Wireless debugging turned on by the app, where adb.grant let it: {on}
 *   adb.start    {station, name, texts}: lent to `station`'s agents (`name`, for the notification); `texts` the
 *                notifications' words (the app's own: src/sfapp/settings/strings.mbt)
 */
final class AdbShare {
    private AdbShare() {}

    static final String STATION = "station";
    /** The service's station while it lends for chats' grants (docs/adb-share.md): to every station they want it on. */
    static final String GRANTS = "*grants";
    static final String NAME = "name";
    static final String CODE = "code";
    static final String PORT = "port";
    static final String START = "dev.mbui.adb.START";
    static final String STOP = "dev.mbui.adb.STOP";
    static final String PAIR = "dev.mbui.adb.PAIR";
    static final String READ = "dev.mbui.adb.READ";
    private static final String CHANNEL = "adb";
    /** What the share's notification opens tapped: settings' 共享调试 page (src/sfbase/notices.mbt open_notice). */
    private static final String OPENS_PAGE = "settings:adb:";
    /** The pairing code's: heads-up, so its field shows over Settings without the shade pulled down. */
    private static final String PAIR_CHANNEL = "adb-pair";
    static final int ID = 7;
    static final int PAIR_ID = 8;
    /** `Settings.Global.ADB_WIFI_ENABLED`, which the SDK hides. */
    private static final String WIRELESS = "adb_wifi_enabled";
    /** still.fail's accent, the notifications' colour (AdbShare.kt). */
    private static final int ACCENT = 0xFFE5704A;

    /** The notifications' words, as the app gave them (adb.start): by their keys, `{n}`, `{name}`, `{error}` filled. */
    private static final Map<String, String> texts = new HashMap<>();

    static String t(String key, String... vars) {
        String s;
        synchronized (texts) {
            s = texts.get(key);
        }
        if (s == null) s = key;
        for (int i = 0; i + 1 < vars.length; i += 2) s = s.replace("{" + vars[i] + "}", vars[i + 1]);
        return s;
    }

    /** Wireless debugging is Android 11's. */
    static boolean supported() {
        return Build.VERSION.SDK_INT >= 30;
    }

    static boolean developerOptions(Context c) {
        return Settings.Global.getInt(c.getContentResolver(), Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1;
    }

    static boolean wirelessOn(Context c) {
        return Settings.Global.getInt(c.getContentResolver(), WIRELESS, 0) == 1;
    }

    /** Whether the app may turn Wireless debugging on itself: the station's adb granted it (`adb.grant`). */
    static boolean canSwitch(Context c) {
        return c.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED;
    }

    static boolean switchOn(Context c) {
        if (!canSwitch(c)) return false;
        try {
            return Settings.Global.putInt(c.getContentResolver(), WIRELESS, 1);
        } catch (Exception e) {
            return false;
        }
    }

    static Uri wirelessUri() {
        return Settings.Global.getUriFor(WIRELESS);
    }

    /** Wireless debugging needs Wi-Fi: Android turns it off without. */
    static boolean onWifi(Context c) {
        ConnectivityManager cm = c.getSystemService(ConnectivityManager.class);
        if (cm == null) return false;
        NetworkCapabilities caps = cm.getNetworkCapabilities(cm.getActiveNetwork());
        return caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI);
    }

    /**
     * Developer options, at Wireless debugging (its row lit up), where it is turned on and paired. `beside`: next to the
     * app when the screen is split (or splits, on large screens), so the app's own field can be used with the dialog open.
     */
    static void openWireless(Context c, boolean beside) {
        int flags = Intent.FLAG_ACTIVITY_NEW_TASK;
        if (beside) flags |= Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT;
        Intent i = new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                .putExtra(":settings:fragment_args_key", "toggle_adb_wireless").addFlags(flags);
        try {
            c.startActivity(i);
        } catch (Exception e) {
            c.startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
    }

    /** Whether the person turned on AdbCodeReader (Accessibility), which fills the pairing code in by itself. */
    static boolean reads(Context c) {
        String on = Settings.Secure.getString(c.getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (on == null) return false;
        ComponentName reader = new ComponentName(c, AdbCodeReader.class);
        for (String s : on.split(":")) {
            if (reader.equals(ComponentName.unflattenFromString(s))) return true;
        }
        return false;
    }

    /** Accessibility's settings, at AdbCodeReader's row where Settings lights it up. */
    static void openReader(Context c) {
        String reader = new ComponentName(c, AdbCodeReader.class).flattenToString();
        Bundle args = new Bundle();
        args.putString(":settings:fragment_args_key", reader);
        Intent i = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(":settings:fragment_args_key", reader).putExtra(":settings:show_fragment_args", args);
        try {
            c.startActivity(i);
        } catch (Exception e) {
            c.startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
    }

    /** What the phone has for it, as adb.phone answers and "native:adb.phone" says. */
    static JSONObject phone(Context c) {
        JSONObject j = new JSONObject();
        try {
            j.put("supported", supported());
            j.put("developer", developerOptions(c));
            j.put("wireless", wirelessOn(c));
            j.put("wifi", onWifi(c));
            j.put("canSwitch", canSwitch(c));
            j.put("reads", reads(c));
        } catch (Exception e) {
            Host.log("adb: " + e);
        }
        return j;
    }

    /** Said to the app by itself: the phone as it is now (Wireless debugging switched, the app back). */
    static void tellPhone(Context c) {
        Native.post("native:adb.phone", phone(c).toString());
    }

    /** The pairing port announced for this app's share while its code is wanted (the service says): AdbCodeReader's. */
    static volatile int pairingPort = -1;
    /** Told as pairingPort changes (AdbCodeReader looks again: the dialog is often open before its port is found). */
    static volatile Runnable onPairingPort;

    static void setPairingPort(int port) {
        if (pairingPort == port) return;
        pairingPort = port;
        Runnable r = onPairingPort;
        if (r != null) new Handler(Looper.getMainLooper()).post(r);
    }

    /** The code AdbCodeReader read off the dialog at `port`, to pair with (the service, once per dialog). */
    static void read(Context c, String code, int port) {
        try {
            c.startService(new Intent(c, AdbShareService.class).setAction(READ).putExtra(CODE, code).putExtra(PORT, port));
        } catch (Exception e) {
            Host.log("adb: " + e);
        }
    }

    /** The native calls put for the app, and the phone said again as it changes; once, as the app starts. */
    static void install(Application app) {
        Context c = app.getApplicationContext();
        Natives.put("adb.phone", (params, reply) -> reply.ok(phone(c).toString()));
        Natives.put("adb.open", (params, reply) -> {
            try {
                JSONObject p = new JSONObject(params);
                if ("reader".equals(p.optString("what"))) openReader(c);
                else openWireless(c, p.optBoolean("beside", false));
                reply.ok("{}");
            } catch (Exception e) {
                reply.fail(String.valueOf(e));
            }
        });
        Natives.put("adb.switch", (params, reply) -> {
            boolean on = switchOn(c);
            reply.ok("{\"on\":" + on + "}");
            tellPhone(c);
        });
        Natives.put("adb.start", (params, reply) -> {
            try {
                JSONObject p = new JSONObject(params);
                JSONObject words = p.optJSONObject("texts");
                if (words != null) {
                    synchronized (texts) {
                        for (java.util.Iterator<String> it = words.keys(); it.hasNext(); ) {
                            String k = it.next();
                            texts.put(k, words.optString(k));
                        }
                    }
                }
                String station = p.optString("station");
                String name = p.optString("name", "station");
                // lent at the tap, as the core has it (the page's switch follows `adbShare`), its ports given as the
                // service finds them: not first once Android has started the service and it has looked for them
                AdbCore.call("adb.share", offer(c, station, null, null), null);
                c.startForegroundService(new Intent(c, AdbShareService.class).setAction(START)
                        .putExtra(STATION, station).putExtra(NAME, name));
                kept(c).edit().putString(STATION, station).putString(NAME, name)
                        .putString(TEXTS, words != null ? words.toString() : "{}")
                        .putLong(UNTIL, System.currentTimeMillis() + 60 * 60_000L).apply();
                reply.ok("{}");
            } catch (Exception e) {
                AdbCore.call("adb.stop", null, null);
                reply.fail(String.valueOf(e));
            }
        });
        Natives.put("adb.texts", (params, reply) -> {
            try {
                JSONObject words = new JSONObject(params);
                synchronized (texts) {
                    for (java.util.Iterator<String> it = words.keys(); it.hasNext(); ) {
                        String k = it.next();
                        texts.put(k, words.optString(k));
                    }
                }
                // (kept for a start with no app shown: the phone started again, lent for the grants before the app is)
                kept(c).edit().putString(GRANT_TEXTS, words.toString()).apply();
                reply.ok("{}");
            } catch (Exception e) {
                reply.fail(String.valueOf(e));
            }
        });
        resume(c, System.currentTimeMillis() + 30_000);
        if (supported()) {
            // 共享调试 on when the process went (the phone started again, the app updated, Android ended it): the core
            // started for it now, whatever started the process, not once the app is next opened; the notification's
            // words as the app gave them last. (Nothing kept of the switch, an app from before it: on where it lent
            // for a grant, as the core takes it.)
            android.content.SharedPreferences was = kept(c);
            boolean on = was.contains(ON) ? was.getBoolean(ON, false) : was.getLong(GRANTS_UNTIL, 0) > System.currentTimeMillis();
            if (on) {
                try {
                    JSONObject words = new JSONObject(kept(c).getString(GRANT_TEXTS, "{}"));
                    synchronized (texts) {
                        for (java.util.Iterator<String> it = words.keys(); it.hasNext(); ) {
                            String k = it.next();
                            if (!texts.containsKey(k)) texts.put(k, words.optString(k));
                        }
                    }
                } catch (Exception ignored) {
                }
                StillfailApp.startAhead(c);
            }
            followSwitch(c, System.currentTimeMillis() + 60_000);
        }
        if (!supported()) return;
        // Wireless debugging switched (by the app, by the person, or by Android as the Wi-Fi goes)
        c.getContentResolver().registerContentObserver(wirelessUri(), false, new ContentObserver(new Handler(Looper.getMainLooper())) {
            @Override
            public void onChange(boolean selfChange) {
                tellPhone(c);
            }
        });
        // back from Settings (Developer options, Accessibility): what may have changed there
        app.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityResumed(Activity a) {
                tellPhone(c);
            }

            @Override
            public void onActivityCreated(Activity a, Bundle b) {}

            @Override
            public void onActivityStarted(Activity a) {}

            @Override
            public void onActivityPaused(Activity a) {}

            @Override
            public void onActivityStopped(Activity a) {}

            @Override
            public void onActivitySaveInstanceState(Activity a, Bundle b) {}

            @Override
            public void onActivityDestroyed(Activity a) {}
        });
    }

    // ---- a share that outlives the app's process ----
    //
    // The app started again while a share was on (it was updated, Android or a crash ended it): lent again to the same
    // station for what was left of its time, as the person asked, not ended with the process. What it is lent to and
    // until when kept on the device from the tap on; let go when the share ends (stopped, its time up: the service's
    // onDestroy), which a process that is killed never reaches.

    private static final String TEXTS = "texts";
    private static final String UNTIL = "until";
    /** When the last of the chats' grants the phone is lent for ends (ms; none: lent for none), and the notification's
     *  words as the app last gave them: kept for the process that starts while one is live (AdbShareService). */
    static final String GRANTS_UNTIL = "grantsUntil";
    /** The 共享调试 switch as the core last said it (`adbShare` `on`): whether a process starting starts the core for it. */
    static final String ON = "on";
    private static final String GRANT_TEXTS = "grantTexts";

    /** Whether the service was started for the switch and not yet seen to end (it ended: AdbShareService). */
    static boolean granting;
    /** Whether the core last said the 共享调试 switch is on (`adbShare` `on`). */
    private static boolean switchedOn;

    /**
     * The service for the switch ended while it is on (its offer refused, say): started again, not left ended until
     * the core next says something of it, or the process goes.
     */
    static void grantsEnded(Context c) {
        granting = false;
        if (!switchedOn) return;
        granting = true;
        try {
            c.startForegroundService(new Intent(c, AdbShareService.class).setAction(START).putExtra(STATION, GRANTS).putExtra(NAME, ""));
        } catch (Exception e) {
            Host.log("adb share: not lent again for the grants: " + e);
            granting = false;
        }
    }

    /**
     * The service started while the 共享调试 switch is on (`adbShare` `on`), once the core runs (asked again each second
     * till then, up to `by`): held up from then, the phone lent for each chat's grant as the core has them; ended as the
     * switch is turned off. The switch kept for a process to come (ON).
     */
    /** Whether the switch is followed now (once per process: the core goes with it). */
    private static boolean following;

    /** The switch followed once the core started (StillfailApp.startAhead), if not yet: whatever started the process. */
    static void coreStarted(Context c) {
        if (supported() && !following) followSwitch(c, System.currentTimeMillis() + 60_000);
    }

    private static void followSwitch(Context c, long by) {
        if (following) return;
        long id = AdbCore.follow("adbShare", value -> {
            if (!(value instanceof JSONObject)) return;
            // (the switch kept on the device not read yet: off there says nothing of it)
            if (!((JSONObject) value).optBoolean("known", true)) return;
            boolean want = ((JSONObject) value).optBoolean("on", false);
            switchedOn = want;
            android.content.SharedPreferences k = kept(c);
            if (!k.contains(ON) || k.getBoolean(ON, false) != want) k.edit().putBoolean(ON, want).apply();
            if (want && !granting) {
                granting = true;
                try {
                    c.startForegroundService(new Intent(c, AdbShareService.class).setAction(START).putExtra(STATION, GRANTS).putExtra(NAME, ""));
                } catch (Exception e) {
                    Host.log("adb share: not lent for the grants: " + e);
                    granting = false;
                }
            } else if (!want) granting = false;
        });
        if (id >= 0) following = true;
        else if (System.currentTimeMillis() < by) new Handler(Looper.getMainLooper()).postDelayed(() -> followSwitch(c, by), 1000);
    }

    static android.content.SharedPreferences kept(Context c) {
        return c.getSharedPreferences("adb-share", Context.MODE_PRIVATE);
    }

    /** The share's end as the core says it (its `until`), kept for the next start. */
    static void keepUntil(Context c, long until) {
        android.content.SharedPreferences k = kept(c);
        if (k.contains(STATION) && k.getLong(UNTIL, 0) != until) k.edit().putLong(UNTIL, until).apply();
    }

    /** The share of the switch's let go (the grants' kept apart: they end as the grants do, AdbShareService). */
    static void letGo(Context c) {
        kept(c).edit().remove(STATION).remove(NAME).remove(TEXTS).remove(UNTIL).apply();
    }

    /**
     * A share kept from a process before lent again, once the core runs (asked again each second till then, up to
     * `by`): with a minute or more of its time left, for what is left; else let go.
     */
    private static void resume(Context c, long by) {
        android.content.SharedPreferences k = kept(c);
        String station = k.getString(STATION, null);
        if (station == null) return;
        long left = k.getLong(UNTIL, 0) - System.currentTimeMillis();
        if (left < 60_000) {
            letGo(c);
            return;
        }
        try {
            JSONObject words = new JSONObject(k.getString(TEXTS, "{}"));
            synchronized (texts) {
                for (java.util.Iterator<String> it = words.keys(); it.hasNext(); ) {
                    String key = it.next();
                    texts.put(key, words.optString(key));
                }
            }
        } catch (Exception ignored) {
        }
        JSONObject offer = offer(c, station, null, null);
        try {
            offer.put("minutes", (int) (left / 60_000));
        } catch (Exception ignored) {
        }
        String name = k.getString(NAME, "station");
        AdbCore.call("adb.share", offer, new AdbCore.Answer() {
            @Override
            public void ok(Object value) {
                try {
                    c.startForegroundService(new Intent(c, AdbShareService.class).setAction(START)
                            .putExtra(STATION, station).putExtra(NAME, name));
                } catch (Exception e) {
                    Host.log("adb share: not lent again: " + e);
                    AdbCore.call("adb.stop", null, null);
                    letGo(c);
                }
            }

            @Override
            public void error(String why) {
                // (the core not running yet: asked again in a second)
                if (why.contains("UnsatisfiedLinkError") && System.currentTimeMillis() < by) {
                    new Handler(Looper.getMainLooper()).postDelayed(() -> resume(c, by), 1000);
                } else {
                    Host.log("adb share: not lent again: " + why);
                    letGo(c);
                }
            }
        });
    }

    /** What `adb.share` is asked with: lent to `station`, adbd's ports as found (null, none found). */
    static JSONObject offer(Context c, String station, Integer connect, Integer pair) {
        JSONObject p = new JSONObject();
        try {
            p.put("station", station);
            if (connect != null) p.put("connect", connect);
            if (pair != null) p.put("pair", pair);
            p.put("device", Build.MODEL);
            p.put("android", Build.VERSION.RELEASE);
            p.put("package", c.getPackageName());
        } catch (Exception ignored) {
        }
        return p;
    }

    static Notification notification(Context c, JSONObject view, String name, String said) {
        return notificationTitled(c, view, t("android-misc.adb.notify.title", "name", name), said);
    }

    /** The share's notification titled `title` (for chats' grants: how many chats it is lent to). */
    static Notification notificationTitled(Context c, JSONObject view, String title, String said) {
        return notificationTitled(c, view, title, said, t("android-misc.adb.stop"));
    }

    /** As notificationTitled, its one action named `stop` (the switch's: 关闭共享调试). */
    static Notification notificationTitled(Context c, JSONObject view, String title, String said, String stopLabel) {
        NotificationManager manager = c.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(CHANNEL, t("android-misc.adb.title"), NotificationManager.IMPORTANCE_LOW));
        // tapped, settings' 共享调试 (its switch and the chats' grants), as a notice's tap opens what it carries (Notices.OPENS)
        Intent page = new Intent(c, MainActivity.class).putExtra(Notices.OPENS, OPENS_PAGE).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent open = PendingIntent.getActivity(c, 0, page, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent stop = PendingIntent.getService(c, 1, new Intent(c, AdbShareService.class).setAction(STOP), PendingIntent.FLAG_IMMUTABLE);
        String text = said != null ? said : line(c, view);
        return new Notification.Builder(c, CHANNEL)
                .setSmallIcon(c.getApplicationInfo().icon)
                .setColor(ACCENT)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(new Notification.Action.Builder(null, stopLabel, stop).build())
                .build();
    }

    /** Whether the pairing dialog is open (its port is announced) and its code still wanted. */
    static boolean pairing(JSONObject view) {
        return view != null && view.has("pairPort") && !view.isNull("pairPort") && !"connected".equals(view.optString("adb"));
    }

    /**
     * The field for the pairing dialog's code, popping up over it (Settings stays in front, so the dialog stays open):
     * `said` in place of the ask, while a code typed is tried or after it failed.
     */
    static Notification pairNotification(Context c, String said) {
        NotificationManager manager = c.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(PAIR_CHANNEL, t("android-misc.adb.pair.channel"), NotificationManager.IMPORTANCE_HIGH));
        PendingIntent pair = PendingIntent.getService(c, 2, new Intent(c, AdbShareService.class).setAction(PAIR),
                PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        RemoteInput input = new RemoteInput.Builder(CODE).setLabel(t("android-misc.adb.code")).build();
        String text = said != null ? said : reads(c) ? t("android-misc.adb.pair.auto") : t("android-misc.adb.typeCode");
        return new Notification.Builder(c, PAIR_CHANNEL)
                .setSmallIcon(c.getApplicationInfo().icon)
                .setColor(ACCENT)
                .setContentTitle(t("android-misc.adb.pair.ask"))
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .addAction(new Notification.Action.Builder(null, t("android-misc.adb.enterCode"), pair).addRemoteInput(input).build())
                .build();
    }

    /** How it stands, in a line. */
    static String line(Context c, JSONObject view) {
        if (view == null || "connecting".equals(view.optString("phase"))) {
            String m = view == null ? "" : view.optString("message", "");
            return m.isEmpty() ? t("android-misc.adb.connecting") : m;
        }
        String adb = view.optString("adb");
        if ("connected".equals(adb)) {
            if (view.has("until") && !view.isNull("until")) {
                long left = Math.max(0, (view.optLong("until") - System.currentTimeMillis()) / 60_000);
                return t("android-misc.adb.connected.left", "n", String.valueOf(left));
            }
            return t("android-misc.adb.connected");
        }
        if ("unpaired".equals(adb)) {
            if (!view.has("pairPort") || view.isNull("pairPort")) return t("android-misc.adb.notPaired");
            return reads(c) ? t("android-misc.adb.pair.auto") : t("android-misc.adb.pair.popped");
        }
        if ("off".equals(adb)) return t("android-misc.adb.off");
        String m = view.optString("message", "");
        return m.isEmpty() ? t("android-misc.adb.attaching") : m;
    }
}
