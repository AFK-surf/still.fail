// Notifications (docs/notifications.md → Clients): one channel (消息), one notification per chat (its tag), opening the
// chat at the message it is about. Local notices are those the core's `notify` says to show while the app is in front
// (MainActivity; client/core-ts/src/attend.ts decides), pushes come from FCM while it is not (Push.kt). 我 → 通知 turns
// both off (kept in the core).
package fail.still.android

import fail.still.android.data.t
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalContext
import fail.still.android.data.Notice
import fail.still.android.data.NotifyView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.I18n
import fail.still.core.CoreException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

object Notifier {
    private const val CHANNEL = "messages"
    /** Every notification has this id; the chat is its tag, so a newer one for a chat replaces the older. */
    private const val ID = 1
    /** The message a notification is about (its seq in the chat), which its tap opens the chat at. */
    const val AT = "fail.still.android.AT"
    /** Where the app kept 我 → 通知 before the core did (AppState.moveNotify). */
    const val FLAG = "notify"

    /** Where the language last followed is kept (AppState's prefs), for a push that wakes the app with no core to ask. */
    private const val LANG = "lang"
    /** Whether this process has followed the core's language (keepLang): then it is the one. */
    @Volatile private var followed = false

    fun keepLang(prefs: SharedPreferences, lang: String?) {
        if (lang == null) return
        followed = true
        if (prefs.getString(LANG, null) != lang) prefs.edit().putString(LANG, lang).apply()
    }

    /** The words, in the language last followed (a push may come with no app started). */
    fun words(context: Context) {
        I18n.load(context)
        if (!followed) context.getSharedPreferences("stillfail", Context.MODE_PRIVATE).getString(LANG, null)?.let(I18n::follow)
    }

    /** Whether MainActivity is started. */
    @Volatile var inFront = false

    fun allowed(context: Context) = Build.VERSION.SDK_INT < 33 ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    /**
     * What the system lets the app show, as the core's `notify.permission` takes it (what every client's notifications
     * page shows): the app's notifications on, off, or not asked yet (`asked`: whether it was, as the core keeps it).
     */
    fun permission(context: Context, asked: Boolean?): String = when {
        manager(context).areNotificationsEnabled() -> "granted"
        Build.VERSION.SDK_INT >= 33 && asked == false -> "default"
        else -> "denied"
    }

    /** A tap opens the chat (`url`) at the message it is about (`seq`; at its usual place without one: an older station or cloud). */
    fun show(context: Context, tag: String, title: String, body: String, url: String, seq: Long?) {
        val manager = manager(context)
        words(context)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, t("android-misc.notify.channel"), NotificationManager.IMPORTANCE_HIGH))
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.CLOUD_ORIGIN.trimEnd('/') + url)).setClass(context, MainActivity::class.java)
            .apply { if (seq != null) putExtra(AT, seq) }
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

    fun show(context: Context, notice: Notice) = show(context, notice.tag, notice.title, notice.body, notice.url, notice.seq)

    /** A chat opened: its notification is read. */
    fun cancel(context: Context, tag: String) = manager(context).cancel(tag, ID)
}

/**
 * While the app is in front: the notices the core's `notify` says to show now (not while off, not for the chat looked
 * at, only of the workspace the app is in; client/core-ts/src/attend.ts), each shown once it is taken (`notice.claim`).
 */
@OptIn(ExperimentalCoroutinesApi::class)
suspend fun showNotices(context: Context, app: AppState) {
    val taken = HashSet<String>()
    snapshotFlow { app.workspace }.flatMapLatest { app.core.topic(Topics.notify(it)) }.collect { state ->
        val json = state.value?.takeIf { it !is JsonNull } ?: return@collect
        val show = try { decode(NotifyView.serializer(), json).show } catch (_: Exception) { return@collect }
        show.filter { taken.add(it.id) }.forEach { notice ->
            val answer = try { app.core.call("notice.claim", buildJsonObject { put("id", notice.id) }) } catch (_: CoreException) { return@forEach }
            if ((answer as? JsonObject)?.get("show")?.jsonPrimitive?.booleanOrNull == true) Notifier.show(context, notice)
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
        if (!granted && !once) app.toast = t("android-misc.notify.allowInSettings", "app" to BuildConfig.APP_NAME)
        // The answer, to the core at once (the activity was not stopped for the system's dialog).
        app.scope.launch {
            try { app.core.call("notify.permission", buildJsonObject { put("state", if (granted) "granted" else "denied") }) } catch (_: CoreException) {}
        }
    }
    val ask = { if (!Notifier.allowed(context) && Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }
    // Once the core says whether it was asked.
    if (once) LaunchedEffect(app.notifyAsked) {
        if (app.notify && app.notifyAsked == false) { app.askedNotify(); ask() }
    }
    return ask
}
