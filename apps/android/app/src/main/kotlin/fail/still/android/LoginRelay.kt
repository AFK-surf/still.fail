// A login's browser step on this phone, kept alive (docs/remote-login.md): a loopback login (gcloud, aws, az…) has the
// phone listen on the command's callback port (the core's relay, client/core-ts station/machine-logins.ts; the listener
// in Kotlin, :core Loopback.kt) while the person signs in in a Custom Tab, then hands the browser's callback to the
// station. Meanwhile the app is in the background (the Custom Tab, or the authenticator app a sign-in sends one to), and
// Android freezes a cached app's process within seconds (the cached apps freezer, on by default from Android 14): a
// frozen process answers nobody, and the browser's callback would hang. So for as long as a listener is open, and only
// then, a foreground service holds the app up and says so in a quiet notification; it is started by the press that opens
// the browser (the app in front, as Android requires) and ends by itself as the last listener closes (the callback
// relayed and ten seconds after, the login ended or cancelled, or the core's fifteen minutes at most).
//
// Its type is `specialUse`: none of the others is this (not a data sync, not media, not a connected device), and
// `shortService`'s three minutes are too short for a sign-in with a second factor.
package fail.still.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import fail.still.android.data.t
import fail.still.core.Loopback
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

object LoginRelay {
    internal const val TITLE = "title"
    private const val CHANNEL = "login"
    internal const val ID = 9
    /** Longer than the core keeps a relay (RELAY_MOST_MS, 15 minutes): the service never outlives its reason. */
    internal const val MOST_MS = 16 * 60_000L

    /** Holds the app up while this phone listens for a login's browser (`title`: 在 Studio 上登录 gcloud). */
    fun start(context: Context, title: String) {
        try {
            context.startForegroundService(Intent(context, LoginRelayService::class.java).putExtra(TITLE, title))
        } catch (e: IllegalStateException) {
            // Not in front after all (ForegroundServiceStartNotAllowedException): the relay listens as long as the app runs.
            Log.w("stillfail-login", "no foreground service for the login's browser", e)
        }
    }

    internal fun notification(context: Context, title: String): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, t("web-main.logins.title"), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFE5704A.toInt())
            .setContentTitle(title)
            .setContentText(t("web-main.logins.waitingBrowser"))
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }
}

/** In the foreground while a login's loopback listener is open (Loopback.open), then gone. */
class LoginRelayService : Service() {
    private val scope = MainScope()
    private var job: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        KeptLang.words(this)
        val shown = LoginRelay.notification(this, intent?.getStringExtra(LoginRelay.TITLE) ?: t("web-main.logins.title"))
        if (Build.VERSION.SDK_INT >= 34) startForeground(LoginRelay.ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(LoginRelay.ID, shown)
        job?.cancel()
        job = scope.launch {
            withTimeoutOrNull(LoginRelay.MOST_MS) { Loopback.open.first { it == 0 } }
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
