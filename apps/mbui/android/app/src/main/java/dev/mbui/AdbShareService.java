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
 * Holds the app up while the phone is lent (a foreground service; still.fail's AdbShareService, AdbShare.kt): finds
 * Wireless debugging's ports and tells the core each time they change, says in its notification how it stands, takes
 * the pairing code typed there (or read off the dialog, AdbCodeReader), and ends when the core's `adbShare` says the
 * phone is lent no longer (stopped, its hour up, the station too old). The core asked through AdbCore, which goes on
 * while the app is behind.
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
    /** The pairing port whose code was read off its dialog and tried: not again for that dialog, whatever came of it. */
    private int read = -1;
    /** Lent to this station: its end said by the core ends the service. */
    private boolean lent;
    /** The offer last made (connect and pair ports): made again only as they change. */
    private String offered;
    /** The connect port the core said nothing listens on, once looked for again for it. */
    private int refused = -1;
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
            android.app.Notification shown = AdbShare.notification(this, null, name, null);
            if (Build.VERSION.SDK_INT >= 34) startForeground(AdbShare.ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            else startForeground(AdbShare.ID, shown);
            begin(s);
        } else if (AdbShare.STOP.equals(action) && AdbShare.GRANTS.equals(station)) {
            // 停止, lent for chats' grants: each taken back (the service ends as none wants it lent)
            org.json.JSONArray grants = view == null ? null : view.optJSONArray("grants");
            if (grants == null || grants.length() == 0) stopSelf();
            else for (int i = 0; i < grants.length(); i++) {
                JSONObject g = grants.optJSONObject(i);
                if (g == null || !"granted".equals(g.optString("status"))) continue;
                try {
                    AdbCore.call("adb.revoke", new JSONObject().put("station", g.optString("station")).put("request", g.optString("id")), null);
                } catch (Exception ignored) {
                }
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
        } else if (AdbShare.READ.equals(action)) {
            // only for the dialog open now, once
            int port = intent.getIntExtra(AdbShare.PORT, -1);
            String code = intent.getStringExtra(AdbShare.CODE);
            if (code != null && port >= 0 && AdbShare.pairing(view) && view.optInt("pairPort", -2) == port && read != port) {
                read = port;
                pair(code);
            }
        }
        return START_NOT_STICKY;
    }

    /** Pairs with the code typed in the notification or read off the dialog, saying how it goes in the notification. */
    private void pair(String code) {
        // said back at once: the notification's field waits (spinning) until it is posted again
        pairNote = AdbShare.t("android-misc.adb.pairing");
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
        manager.notify(AdbShare.ID, AdbShare.GRANTS.equals(station)
                ? AdbShare.notificationTitled(this, view, name, note)
                : AdbShare.notification(this, view, name, note));
        boolean pairing = AdbShare.pairing(view);
        int port = view == null ? -1 : view.optInt("pairPort", -1);
        AdbShare.setPairingPort(pairing ? port : -1);
        if (pairing) {
            // another dialog: popped up afresh (only once per dialog, not as the minutes go)
            if (pairShown != port) {
                manager.cancel(AdbShare.PAIR_ID);
                pairNote = null;
            }
            pairShown = port;
            manager.notify(AdbShare.PAIR_ID, AdbShare.pairNotification(this, pairNote));
        } else if (pairShown >= 0) {
            manager.cancel(AdbShare.PAIR_ID);
            pairShown = -1;
        }
    }

    private void begin(String to) {
        end();
        station = to;
        lent = false;
        offered = null;
        refused = -1;
        // granted before (`adb.grant`): on by itself, as Android allows only on Wi-Fi
        if (!AdbShare.wirelessOn(this) && AdbShare.onWifi(this)) AdbShare.switchOn(this);
        ports = new AdbPorts(this, this::offer);
        ports.start();
        // ports as DNS-SD last said them, but none while Wireless debugging is off: its announcement can outlive it
        // (2026-10-17, an OPPO: off in Settings, its port still offered, the station's adb dialling a refused port)
        observer = new ContentObserver(main) {
            @Override
            public void onChange(boolean selfChange) {
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
            boolean here = AdbShare.GRANTS.equals(station)
                    ? v.optJSONArray("wanted") != null && v.optJSONArray("wanted").length() > 0
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
                name = AdbShare.t("android-misc.adb.notify.chats", "n", String.valueOf(chats));
                // (kept: the process that starts while one is live lends for them at once, AdbShare.install)
                android.content.SharedPreferences k = AdbShare.kept(this);
                if (chats == 0) k.edit().remove(AdbShare.GRANTS_UNTIL).apply();
                else if (k.getLong(AdbShare.GRANTS_UNTIL, 0) != until) k.edit().putLong(AdbShare.GRANTS_UNTIL, until).apply();
            }
            if (here) lent = true;
            if (here && v.has("until") && !v.isNull("until")) AdbShare.keepUntil(this, v.optLong("until"));
            if (lent && !here) {
                AdbShare.setPairingPort(-1);
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

    private void end() {
        main.removeCallbacks(minute);
        if (follow >= 0) AdbCore.unfollow(follow);
        follow = -1;
        if (ports != null) ports.stop();
        ports = null;
        if (observer != null) getContentResolver().unregisterContentObserver(observer);
        observer = null;
    }

    @Override
    public void onDestroy() {
        getSystemService(NotificationManager.class).cancel(AdbShare.PAIR_ID);
        AdbShare.setPairingPort(-1);
        end();
        probes.shutdownNow();
        // gone with the service, whatever ended it; not lent again as the app next starts
        AdbCore.call("adb.stop", null, null);
        AdbShare.letGo(this);
        super.onDestroy();
    }
}
