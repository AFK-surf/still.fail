package dev.mbui;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;

/**
 * The system's notifications (src/host/notify.mbt), as still.fail's Android app shows them (its app/Notices.kt
 * Notifier): one channel ("messages", named as the app says), one notification per tag (the same id for all, the tag
 * telling them apart: a newer one for a chat replaces the older), tapped it opens MainActivity with what it was shown
 * with ({@link #OPENS}), which the app reads once ({@link #text} 0). POST_NOTIFICATIONS is asked for from the activity
 * (Android 13 on); its answer comes back through {@link MainActivity#onRequestPermissionsResult}. No push service is
 * linked (no Firebase in this build): no token, no push delivered.
 */
final class Notices {
    private static final String CHANNEL = "messages";
    /** Every notification has this id; its tag tells them apart. */
    private static final int ID = 1;
    /** The extra a notification's tap carries: what it opens, as the app gave it. */
    static final String OPENS = "dev.mbui.NOTICE_OPENS";
    /** The request code of the permission's ask. */
    static final int ASK = 7101;

    /** A notification tapped, not read by the app yet ("" none). */
    static volatile String opened = "";
    /** The system's answer to the last ask, not read yet: -1 none, 0 refused, 1 allowed. */
    static volatile int answer = -1;

    private static Context context() {
        MainActivity a = Host.activity;
        return a != null ? a.getApplicationContext() : null;
    }

    private static NotificationManager manager(Context c) {
        return c.getSystemService(NotificationManager.class);
    }

    /** Shown in `channel` (made, or renamed, as it is shown), replacing any of the same tag (Notifier.show). */
    static void show(String channel, String tag, String title, String body, String opens) {
        Context c = context();
        if (c == null) return;
        NotificationManager m = manager(c);
        m.createNotificationChannel(new NotificationChannel(CHANNEL, channel, NotificationManager.IMPORTANCE_HIGH));
        Intent open = new Intent(c, MainActivity.class).putExtra(OPENS, opens)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        // one each tag (its extras alone would not tell two apart)
        PendingIntent tap = PendingIntent.getActivity(c, tag.hashCode(), open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new Notification.Builder(c, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFFE5704A)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .build();
        m.notify(tag, ID, n);
        Host.log("NOTICE " + tag + "\t" + title + "\t" + body);
    }

    /** A chat opened: its notification goes (Notifier.cancel). */
    static void cancel(String tag) {
        Context c = context();
        if (c == null) return;
        NotificationManager m = manager(c);
        for (StatusBarNotification s : m.getActiveNotifications()) {
            if (tag.equals(s.getTag())) Host.log("NOTICE CANCEL " + tag);
        }
        m.cancel(tag, ID);
    }

    /** 0: what the system allows (1 granted, 2 denied, 3 off and maybe never asked); 1: ask (1 asked); 2: the answer, once. */
    static int state(int what) {
        Context c = context();
        switch (what) {
            case 0:
                if (c == null) return 0;
                // as Notifier.permission: off, from Android 13 on it may not have been asked yet (the app knows)
                if (manager(c).areNotificationsEnabled()) return 1;
                return Build.VERSION.SDK_INT >= 33 ? 3 : 2;
            case 1: {
                MainActivity a = Host.activity;
                if (a == null || Build.VERSION.SDK_INT < 33
                        || a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return 0;
                Host.main.post(() -> a.requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS }, ASK));
                return 1;
            }
            case 2: {
                int r = answer;
                answer = -1;
                return r;
            }
            default:
                return 0;
        }
    }

    /** 0: a notification tapped, once; 1: the push token; 2: a push delivered, once (none: no push service here). */
    static String text(int what) {
        if (what != 0) return "";
        String o = opened;
        opened = "";
        return o;
    }

    /**
     * The activity started or brought back by a notification's tap: what it opens, kept for the app; or by a link (an
     * http(s) ACTION_VIEW the manifest takes: one of the app's links tapped in another app), posted to the app on its
     * system channel ({"link": url}: src/host/system.mbt), so a run's tape has it. Each is taken off the intent once
     * told (as still.fail's MainActivity.handle sets an empty one).
     */
    static void from(Intent intent) {
        if (intent != null && Intent.ACTION_VIEW.equals(intent.getAction()) && intent.getData() != null
                && ("https".equals(intent.getData().getScheme()) || "http".equals(intent.getData().getScheme()))) {
            String link = intent.getData().toString();
            intent.setData(null);
            Host.log("LINK OPENED " + link);
            try {
                Native.post("system", new org.json.JSONObject().put("link", link).toString());
            } catch (org.json.JSONException ignored) {
            }
            return;
        }
        String o = intent != null ? intent.getStringExtra(OPENS) : null;
        if (o == null) return;
        intent.removeExtra(OPENS);
        opened = o;
        Host.log("NOTICE TAP " + o.replace('\n', ' '));
        Host.requestFrame();
    }

    /** The permission's answer (MainActivity). */
    static void answered(boolean granted) {
        answer = granted ? 1 : 0;
        Host.requestFrame();
    }

    /**
     * A scripted run (src/ui/drive.mbt `notice`, `noticed`): whether this app shows a notification whose title or
     * words hold `words`; `tap`: tapped (its PendingIntent sent, as the shade's tap sends it, and taken off as
     * setAutoCancel would).
     */
    static int drive(boolean tap, String words) {
        Context c = context();
        if (c == null) return 0;
        NotificationManager m = manager(c);
        for (StatusBarNotification s : m.getActiveNotifications()) {
            Bundle x = s.getNotification().extras;
            CharSequence title = x.getCharSequence(Notification.EXTRA_TITLE);
            CharSequence body = x.getCharSequence(Notification.EXTRA_TEXT);
            boolean holds = (title != null && title.toString().contains(words)) || (body != null && body.toString().contains(words));
            if (!holds) continue;
            if (!tap) return 1;
            try {
                s.getNotification().contentIntent.send();
            } catch (PendingIntent.CanceledException e) {
                return 0;
            }
            m.cancel(s.getTag(), s.getId());
            return 1;
        }
        return 0;
    }
}
