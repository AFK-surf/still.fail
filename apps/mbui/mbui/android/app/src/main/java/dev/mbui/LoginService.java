package dev.mbui;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

/**
 * Holds the app up while a loopback listener is open ({@link Loopback}), as still.fail's app does (ember
 * apps/android LoginRelay.kt): while the person signs in in the browser the app is in the background, and Android
 * freezes a cached app's process within seconds (the cached apps freezer, on by default from Android 14); a frozen
 * process answers nobody, and the browser's way back would hang. So for as long as one listens, and only then, a
 * foreground service of type {@code specialUse} keeps the process running with a quiet notification. It is started as
 * the first listener opens (the app in front, as Android requires; when it is not, the listener works as long as the
 * process runs) and ends as the last one closes, or after 16 minutes at most.
 */
public final class LoginService extends Service {
    private static final String CHANNEL = "login";
    private static final int ID = 9;
    private static final long MOST_MS = 16 * 60_000L;
    /**
     * What its notice says (@hostapi.hold_words, the app's words: still.fail's LoginRelay.kt notification): its channel's
     * name, its title (在 Studio 上登录 gcloud), its line.
     */
    private static volatile String channelName = "Login", title = "Login", body = "";

    static void words(String channel, String t, String b) {
        if (!channel.isEmpty()) channelName = channel;
        if (!t.isEmpty()) title = t;
        body = b;
    }

    /** A listener is open (the service asked for or running); its instance once started. */
    private static boolean running;
    private static LoginService started;
    private final Handler later = new Handler(Looper.getMainLooper());

    /** Whether a listener is open: a sign-in waits in the browser (Updates: the app not put in place meanwhile). */
    static synchronized boolean listening() {
        return running;
    }

    /** {@code n} listeners are open now (Loopback, any thread). */
    static synchronized void listening(int n) {
        Context app = Host.activity != null ? Host.activity.getApplicationContext() : null;
        if (app == null) return;
        if (n > 0 && !running) {
            try {
                app.startForegroundService(new Intent(app, LoginService.class));
                running = true;
            } catch (RuntimeException e) {
                // not in front (ForegroundServiceStartNotAllowedException): it listens as long as the process runs
                Host.log("login: no foreground service while listening: " + e);
            }
        } else if (n == 0 && running) {
            running = false;
            // Stopped once it is in the foreground (one stopped before it gets there takes the app down with it):
            // now when it is, else as it gets there.
            LoginService s = started;
            if (s != null) s.later.post(() -> {
                synchronized (LoginService.class) {
                    if (running) return;  // another opened meanwhile
                }
                s.stopSelf();
            });
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_LOW));
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE);
        Notification shown = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFFE5704A)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(open)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(ID, shown);
        later.removeCallbacksAndMessages(null);
        synchronized (LoginService.class) {
            if (!running) {
                stopSelf();
                return START_NOT_STICKY;
            }
            started = this;
        }
        Host.log("login: holding the app up while the browser signs in");
        later.postDelayed(() -> {
            synchronized (LoginService.class) {
                running = false;
            }
            stopSelf();
        }, MOST_MS);
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        later.removeCallbacksAndMessages(null);
        synchronized (LoginService.class) {
            if (started == this) started = null;
            running = false;
        }
        Host.log("login: no longer held up");
        super.onDestroy();
    }
}
