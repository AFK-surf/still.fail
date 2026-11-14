package dev.mbui;

import android.app.NotificationManager;
import android.app.RemoteInput;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.database.ContentObserver;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import org.json.JSONObject;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Holds the app up while the phone is lent (a foreground service; still.fail's AdbShareService): finds
 * Wireless debugging's ports and tells the core each time they change, says in its notification how it stands, takes
 * the pairing code typed there, has a station that newly holds the phone let the app turn Wireless debugging on itself
 * (`adb.grant`), and ends when the core's `adbShare` says the phone is lent no longer (stopped, its hour up, the station
 * too old). The core asked through AdbCore, which goes on while the app is behind.
 */
public final class AdbShareService extends Service {
    private final Handler main = new Handler(Looper.getMainLooper());
    /** Which of adb's ports announced takes a connection: off the main thread (a socket), one at a time. */
    private final ExecutorService probes = Executors.newSingleThreadExecutor();
    private AdbPorts ports;
    private ContentObserver observer;
    private long follow = -1;
    private String station = "";
    private String name = "";
    private JSONObject view;
    /** What the notification says in place of how it stands: why sharing failed. */
    private String note;
    /** What the pairing notification says in place of its ask: a pairing under way, why one failed. */
    private String pairNote;
    /** The pairing port its notification popped up for: a dialog opened again pops it up again. */
    private int pairShown = -1;
    /** The stations whose adb held the phone as the core last said (`adbShare`): one newly holding it asked once. */
    private final java.util.Set<String> held = new java.util.HashSet<>();
    /** Lent to this station: its end said by the core ends the service. */
    private boolean lent;
    /** The offer last made (connect and pair ports): made again only as they change. */
    private String offered;
    /** The connect port the core said nothing listens on, once looked for again for it. */
    private int refused = -1;
    /** For the switch: no chat's grant lends the phone now (the notification says so in place of how it stands). */
    private boolean idle;
    /** For the switch: Wi-Fi coming, Wireless debugging turned on again (Android turns it off as the Wi-Fi goes). */
    private android.net.ConnectivityManager.NetworkCallback wifi;
    /** What each notification says as last posted: posted again only as it changes, or as it was swiped away. */
    private String said;
    private String pairSaid;
    /** 还剩 N 分钟, as the minutes go. */
    private final Runnable minute = new Runnable() {
        @Override
        public void run() {
            say();
            main.postDelayed(this, 60_000);
        }
    };

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (AdbShare.START.equals(action)) {
            String s = intent.getStringExtra(AdbShare.STATION);
            if (s == null || s.isEmpty()) return START_NOT_STICKY;
            name = intent.getStringExtra(AdbShare.NAME);
            if (name == null) name = "station";
            // already lending for the grants: nothing to begin again
            if (AdbShare.GRANTS.equals(s) && AdbShare.GRANTS.equals(station) && ports != null) return START_NOT_STICKY;
            android.app.Notification shown = AdbShare.GRANTS.equals(s)
                    ? AdbShare.notificationTitled(this, null, AdbShare.t("android-misc.adb.notify.on"), AdbShare.t("android-misc.adb.connecting"), AdbShare.t("android-misc.adb.turnOff"))
                    : AdbShare.notification(this, null, name, null);
            if (Build.VERSION.SDK_INT >= 34) startForeground(AdbShare.ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            else startForeground(AdbShare.ID, shown);
            said = null;
            begin(s);
        } else if (AdbShare.STOP.equals(action) && AdbShare.GRANTS.equals(station)) {
            // 关闭共享调试: the switch turned off (the service ends as the core says so; the grants stay, lent to none)
            try {
                AdbCore.call("adb.on", new JSONObject().put("on", false), new AdbCore.Answer() {
                    @Override
                    public void ok(Object value) {}

                    @Override
                    public void error(String why) {
                        stopSelf();
                    }
                });
            } catch (Exception e) {
                stopSelf();
            }
        } else if (AdbShare.STOP.equals(action)) {
            AdbCore.call("adb.stop", null, new AdbCore.Answer() {
                @Override
                public void ok(Object value) {}

                @Override
                public void error(String why) {
                    stopSelf();
                }
            });
        } else if (AdbShare.PAIR.equals(action)) {
            Bundle got = RemoteInput.getResultsFromIntent(intent);
            CharSequence code = got == null ? null : got.getCharSequence(AdbShare.CODE);
            pair(code == null ? "" : code.toString());
        }
        return START_NOT_STICKY;
    }

    /** Pairs with the code typed in the notification, saying how it goes in the notification. */
    private void pair(String code) {
        // said back at once: the notification's field waits (spinning) until it is posted again
        pairNote = AdbShare.t("android-misc.adb.pairing");
        pairSaid = null;
        say();
        StringBuilder digits = new StringBuilder();
        for (char ch : code.toCharArray()) if (ch >= '0' && ch <= '9') digits.append(ch);
        JSONObject p = new JSONObject();
        try {
            p.put("code", digits.toString());
        } catch (Exception ignored) {
        }
        AdbCore.call("adb.pair", p, new AdbCore.Answer() {
            @Override
            public void ok(Object value) {
                pairNote = AdbShare.t("android-misc.adb.paired");
                say();
            }

            @Override
            public void error(String why) {
                pairNote = AdbShare.t("android-misc.adb.pairFailed", "error", why);
                say();
            }
        });
    }

    /** The notifications again, as it stands now (or as `note` and `pairNote` say). */
    private void say() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        said = post(manager, AdbShare.ID, said, AdbShare.GRANTS.equals(station)
                ? AdbShare.notificationTitled(this, view, name, note != null ? note : idle ? AdbShare.t("android-misc.adb.notify.idle") : AdbShare.screens(view), AdbShare.t("android-misc.adb.turnOff"))
                : AdbShare.notification(this, view, name, note));
        boolean pairing = AdbShare.pairing(view);
        int port = view == null ? -1 : view.optInt("pairPort", -1);
        if (pairing) {
            // another dialog: popped up afresh (only once per dialog, not as the minutes go)
            if (pairShown != port) {
                manager.cancel(AdbShare.PAIR_ID);
                pairNote = null;
                pairSaid = null;
            }
            pairShown = port;
            pairSaid = post(manager, AdbShare.PAIR_ID, pairSaid, AdbShare.pairNotification(this, pairNote));
        } else if (pairShown >= 0) {
            manager.cancel(AdbShare.PAIR_ID);
            pairShown = -1;
            pairSaid = null;
        }
    }

    /**
     * `shown` posted unless it says what `before` said and is still up: the core's view changes with what no notification
     * says (a tunnel opened, a grant), and each one posted gets a new time, which can move its icon among the status bar's.
     * What it says now, for the next one.
     */
    private static String post(NotificationManager manager, int id, String before, android.app.Notification shown) {
        StringBuilder now = new StringBuilder();
        now.append(shown.extras.getCharSequence(android.app.Notification.EXTRA_TITLE)).append('\n');
        now.append(shown.extras.getCharSequence(android.app.Notification.EXTRA_TEXT));
        if (shown.actions != null) for (android.app.Notification.Action a : shown.actions) now.append('\n').append(a.title);
        String text = now.toString();
        if (text.equals(before)) {
            for (android.service.notification.StatusBarNotification up : manager.getActiveNotifications()) {
                if (up.getId() == id) return text;
            }
        }
        manager.notify(id, shown);
        return text;
    }

    private void begin(String to) {
        end();
        station = to;
        lent = false;
        offered = null;
        refused = -1;
        // granted before (`adb.grant`): on by itself, as Android allows only on Wi-Fi; for the switch, on again each time it
        // goes (the phone started again, the Wi-Fi changed: 2026-10-30, 「开启后永远开启」)
        keepWireless();
        if (AdbShare.GRANTS.equals(to)) {
            android.net.ConnectivityManager cm = getSystemService(android.net.ConnectivityManager.class);
            wifi = new android.net.ConnectivityManager.NetworkCallback() {
                @Override
                public void onCapabilitiesChanged(android.net.Network network, android.net.NetworkCapabilities caps) {
                    main.post(AdbShareService.this::keepWireless);
                }
            };
            try {
                cm.registerDefaultNetworkCallback(wifi);
            } catch (Exception e) {
                Host.log("adb share: Wi-Fi not followed: " + e);
                wifi = null;
            }
        }
        ports = new AdbPorts(this, this::offer);
        ports.start();
        // ports as DNS-SD last said them, but none while Wireless debugging is off: its announcement can outlive it
        // (2026-10-17, an OPPO: off in Settings, its port still offered, the station's adb dialling a refused port)
        observer = new ContentObserver(main) {
            @Override
            public void onChange(boolean selfChange) {
                if (AdbShare.GRANTS.equals(station)) keepWireless();
                offer();
            }
        };
        getContentResolver().registerContentObserver(AdbShare.wirelessUri(), false, observer);
        main.postDelayed(minute, 60_000);
        // until the core says it is lent no longer (it says so first, before the offer is made)
        follow = AdbCore.follow("adbShare", value -> {
            if (!(value instanceof JSONObject)) return;
            JSONObject v = (JSONObject) value;
            view = v;
            grantNewlyHeld(v);
            if ("connected".equals(v.optString("adb"))) {
                note = null;
                pairNote = null;
            }
            // nothing at the connect port offered: adbd's ports looked for again, once for that port
            int gone = v.optInt("refusedPort", -1);
            if (gone <= 0) refused = -1;
            else if (gone != refused && ports != null) {
                refused = gone;
                ports.again();
            }
            // (for the grants, a core just started that has not read those kept on the device yet: none wanted there
            // is not none granted, and it is lent on as it was)
            if (AdbShare.GRANTS.equals(station) && !v.optBoolean("known", true)) {
                say();
                return;
            }
            // (for the switch: held up while it is on, lent as the grants are)
            boolean here = AdbShare.GRANTS.equals(station)
                    ? v.optBoolean("on", false)
                    : v.optBoolean("sharing") && station.equals(v.optString("station"));
            if (AdbShare.GRANTS.equals(station)) {
                org.json.JSONArray grants = v.optJSONArray("grants");
                int chats = 0;
                long until = 0;
                if (grants != null) for (int i = 0; i < grants.length(); i++) {
                    JSONObject g = grants.optJSONObject(i);
                    if (!"granted".equals(g.optString("status"))) continue;
                    chats++;
                    until = Math.max(until, g.optLong("exp", 0) * 1000);
                }
                name = chats == 0 ? AdbShare.t("android-misc.adb.notify.on") : AdbShare.t("android-misc.adb.notify.chats", "n", String.valueOf(chats));
                idle = chats == 0;
                // (kept: the process that starts while one is live lends for them at once, AdbShare.install)
                android.content.SharedPreferences k = AdbShare.kept(this);
                if (chats == 0) k.edit().remove(AdbShare.GRANTS_UNTIL).apply();
                else if (k.getLong(AdbShare.GRANTS_UNTIL, 0) != until) k.edit().putLong(AdbShare.GRANTS_UNTIL, until).apply();
            }
            if (here) lent = true;
            if (here && v.has("until") && !v.isNull("until")) AdbShare.keepUntil(this, v.optLong("until"));
            if (lent && !here) {
                if (AdbShare.GRANTS.equals(station) || !v.has("station") || v.isNull("station")) stopSelf();
                return;
            }
            say();
        });
        offer();
    }

    /** The ports as they are now, given to the core when they changed: the connect port that takes a connection. */
    private void offer() {
        if (ports == null) return;
        boolean on = AdbShare.wirelessOn(this);
        List<Integer> connects = on ? ports.connects() : java.util.Collections.emptyList();
        Integer pair = on ? ports.pair() : null;
        String to = station;
        probes.execute(() -> {
            Integer connect = AdbPorts.live(connects);
            main.post(() -> {
                if (!to.equals(station) || ports == null) return;
                String key = connect + "/" + pair;
                if (key.equals(offered)) return;
                offered = key;
                // for the grants: the ports, lent with them to every station a grant wants it on
                boolean grants = AdbShare.GRANTS.equals(station);
                AdbCore.call(grants ? "adb.ports" : "adb.share", AdbShare.offer(this, grants ? "" : station, connect, pair), new AdbCore.Answer() {
                    @Override
                    public void ok(Object value) {}

                    @Override
                    public void error(String why) {
                        note = AdbShare.t("android-misc.adb.shareFailed", "error", why);
                        say();
                        stopSelf();
                    }
                });
            });
        });
    }

    /**
     * Each station whose adb holds the phone now and did not as the core last said (`adbShare`'s own and its `lends`:
     * offered, adb connected) asked once to let the app turn Wireless debugging on itself, while it may not yet: everyone
     * lending needs it (2026-11-11, so it is not asked of the person). No timer and no retry: the next time a station
     * comes to hold the phone asks again. The phone refusing it (MIUI, ColorOS: the core's `adb_grant_refused`) kept and
     * said in `adb.phone` (`switchRefused`): 开启无线调试 says which switch of Developer options lets the app; anything
     * else logged.
     */
    private void grantNewlyHeld(JSONObject v) {
        java.util.Set<String> now = new java.util.HashSet<>();
        if (v.optBoolean("sharing") && holds(v)) now.add(v.optString("station"));
        org.json.JSONArray lends = v.optJSONArray("lends");
        if (lends != null) for (int i = 0; i < lends.length(); i++) {
            JSONObject l = lends.optJSONObject(i);
            if (l != null && holds(l)) now.add(l.optString("station"));
        }
        now.remove("");
        for (String to : now) if (!held.contains(to) && !AdbShare.canSwitch(this)) grant(to);
        held.clear();
        held.addAll(now);
    }

    private static boolean holds(JSONObject lend) {
        return "offered".equals(lend.optString("phase")) && "connected".equals(lend.optString("adb"));
    }

    private void grant(String to) {
        JSONObject p = new JSONObject();
        try {
            p.put("station", to);
        } catch (Exception ignored) {
        }
        android.content.Context c = getApplicationContext();
        AdbCore.call("adb.grant", p, new AdbCore.Answer() {
            @Override
            public void ok(Object value) {
                AdbShare.switchRefused = false;
                AdbShare.tellPhone(c);
            }

            @Override
            public void error(String why) {
                error(why, "");
            }

            @Override
            public void error(String why, String code) {
                Host.log("adb share: the app not let turn Wireless debugging on: " + why);
                if (!"adb_grant_refused".equals(code) || AdbShare.switchRefused) return;
                AdbShare.switchRefused = true;
                AdbShare.tellPhone(c);
            }
        });
    }

    /** Wireless debugging on, where it is off, the phone on Wi-Fi and the app may turn it on. */
    private void keepWireless() {
        if (!AdbShare.wirelessOn(this) && AdbShare.onWifi(this)) AdbShare.switchOn(this);
    }

    private void end() {
        main.removeCallbacks(minute);
        if (wifi != null) {
            try {
                getSystemService(android.net.ConnectivityManager.class).unregisterNetworkCallback(wifi);
            } catch (Exception ignored) {
            }
        }
        wifi = null;
        if (follow >= 0) AdbCore.unfollow(follow);
        follow = -1;
        if (ports != null) ports.stop();
        ports = null;
        if (observer != null) getContentResolver().unregisterContentObserver(observer);
        observer = null;
        held.clear();
    }

    @Override
    public void onDestroy() {
        getSystemService(NotificationManager.class).cancel(AdbShare.PAIR_ID);
        end();
        probes.shutdownNow();
        // gone with the service, whatever ended it; not lent again as the app next starts. Ended for the grants while
        // they still want it (its offer refused, say): started again a moment later (AdbShare.grantsEnded), not left
        // ended till the process goes
        boolean grants = AdbShare.GRANTS.equals(station);
        AdbCore.call("adb.stop", null, null);
        AdbShare.letGo(this);
        super.onDestroy();
        if (grants) {
            android.content.Context app = getApplicationContext();
            new Handler(Looper.getMainLooper()).postDelayed(() -> AdbShare.grantsEnded(app), 2_000);
        }
    }
}
