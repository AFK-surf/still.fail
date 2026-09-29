// Notifications (docs/notifications.md → Clients): one channel (消息), one notification per chat (its tag), opening the
// chat as its link would. Local notices come from the core's `notices` topic while the app is in front (MainActivity);
// pushes from FCM while it is not (Push.kt). 我 → 通知 turns both off.
package fail.still.android

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import fail.still.android.data.ChatOf
import fail.still.android.data.Notice
import fail.still.android.data.NoticesView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import kotlinx.serialization.json.JsonNull

object Notifier {
    private const val CHANNEL = "messages"
    /** Every notification has this id; the chat is its tag, so a newer one for a chat replaces the older. */
    private const val ID = 1
    /** 我 → 通知, kept with the app's other settings (AppState.notify). */
    const val FLAG = "notify"

    /** Whether MainActivity is started: local notices are shown then, pushes are not. */
    @Volatile var inFront = false

    fun enabled(context: Context) = context.getSharedPreferences("stillfail", Context.MODE_PRIVATE).getBoolean(FLAG, true)

    fun allowed(context: Context) = Build.VERSION.SDK_INT < 33 ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    /** `url` is the chat's path (/o/<workspace>/<station>/<session>): tapped, MainActivity opens it as that link. */
    fun show(context: Context, tag: String, title: String, body: String, url: String) {
        val manager = manager(context)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "消息", NotificationManager.IMPORTANCE_HIGH))
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.CLOUD_ORIGIN.trimEnd('/') + url)).setClass(context, MainActivity::class.java)
        val tap = PendingIntent.getActivity(context, tag.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFE5704A.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .build()
        manager.notify(tag, ID, notification)
    }

    fun show(context: Context, notice: Notice) = show(context, notice.tag, notice.title, notice.body, notice.url)

    /** A chat opened: its notification is read. */
    fun cancel(context: Context, tag: String) = manager(context).cancel(tag, ID)
}

/**
 * The core's `notices` while the app is in front: the first value is old news; each later item not seen before is
 * shown, unless its chat is the page on top or notifications are off.
 */
suspend fun showNotices(context: Context, app: AppState) {
    var seen: MutableSet<String>? = null
    app.core.topic(Topics.notices).collect { state ->
        val json = state.value?.takeIf { it !is JsonNull } ?: return@collect
        val items = try { decode(NoticesView.serializer(), json).items } catch (_: Exception) { return@collect }
        val known = seen
        seen = items.mapTo(known ?: HashSet()) { it.id }
        if (known == null) return@collect
        items.filter { it.id !in known }.forEach { notice ->
            val top = app.stack.lastOrNull() as? Screen.Chat
            val open = top != null && top.station == notice.station && (top.of as? ChatOf.Session)?.key == notice.session
            if (!open && app.notify) Notifier.show(context, notice)
        }
    }
}

/**
 * Asks for POST_NOTIFICATIONS once, the first time the app is signed in with notifications on; `ask` is also what
 * 我 → 通知 turned on calls.
 */
@Composable
fun rememberNotificationAsk(app: AppState, once: Boolean): () -> Unit {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted && !once) app.toast = "在系统设置里允许 still.fail 发通知"
    }
    val ask = { if (!Notifier.allowed(context) && Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }
    if (once) LaunchedEffect(Unit) {
        if (app.notify && !app.flag("notifyAsked", false)) { app.setFlag("notifyAsked", true); ask() }
    }
    return ask
}
