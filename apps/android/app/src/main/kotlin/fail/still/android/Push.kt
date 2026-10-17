// Pushes while the app is not in front: Firebase Cloud Messaging, set up by hand from BuildConfig (FCM_*: gradle
// properties or apps/android/firebase.properties) rather than google-services.json. With them empty FCM is off and
// only local notices are shown.
package fail.still.android

import android.content.Context
import android.os.SystemClock
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import fail.still.android.data.NotifyView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.coroutines.resume

object Push {
    val configured = BuildConfig.FCM_PROJECT_ID.isNotEmpty() && BuildConfig.FCM_APP_ID.isNotEmpty() &&
        BuildConfig.FCM_API_KEY.isNotEmpty() && BuildConfig.FCM_SENDER_ID.isNotEmpty()

    /** Firebase for this process, once; false when the build has no FCM settings. */
    @Synchronized
    fun init(context: Context): Boolean {
        if (!configured) return false
        if (FirebaseApp.getApps(context).isEmpty()) {
            val options = FirebaseOptions.Builder()
                .setProjectId(BuildConfig.FCM_PROJECT_ID)
                .setApplicationId(BuildConfig.FCM_APP_ID)
                .setApiKey(BuildConfig.FCM_API_KEY)
                .setGcmSenderId(BuildConfig.FCM_SENDER_ID)
                .build()
            FirebaseApp.initializeApp(context.applicationContext, options)
        }
        return true
    }

    /**
     * This device's token as the core wants it (its `notify` says `push`): registered with every signed-in account, or
     * taken off them. The token is what still.fail cloud sends to (FCM HTTP v1); firebase-messaging 25.1 deprecated it
     * for registration by installation id (FID), which still works with tokens: moved over when the cloud sends that way.
     * `wanted`: what the core has just answered, else what its `notify` says.
     */
    @Suppress("DEPRECATION")
    suspend fun sync(context: Context, core: StillFailCore, wanted: Boolean? = null) {
        try {
            val push = wanted ?: core.topic(Topics.notify()).first { it.value != null || it.error != null }.value?.takeIf { it !is JsonNull }
                ?.let { runCatching { decode(NotifyView.serializer(), it).push }.getOrNull() } ?: return
            if (!push) { core.call("push.unregister"); return }
            if (!init(context)) return
            val token = suspendCancellableCoroutine<String?> { done ->
                FirebaseMessaging.getInstance().token.addOnCompleteListener { done.resume(if (it.isSuccessful) it.result else null) }
            } ?: return
            register(core, token)
        } catch (_: CoreException) {
            // An older core without push, or still.fail cloud not reached: tried again on the next start.
        }
    }

    suspend fun register(core: StillFailCore, token: String) {
        core.call("push.register", buildJsonObject { put("kind", "fcm"); put("token", token) })
    }
}

/** How long a push keeps the app running to bring what it is about (FCM gives a high-priority message some 10 s). */
private const val BRING_MS = 8_000L

/** When a push last woke the core while the app was off screen (elapsedRealtime). */
private var woke: Long? = null

/**
 * FCM's side: a new token is registered; a notice is shown while the app is not in front (in front, local ones are),
 * and what it is about brought onto the device.
 */
class PushService : FirebaseMessagingService() {
    override fun onCreate() {
        Crashes.install(applicationContext)
        Push.init(this)
        super.onCreate()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        // Called on FCM's worker thread: the core may not be running yet (no app in front). With notifications off it
        // takes none.
        runBlocking {
            withTimeoutOrNull(30_000) {
                try {
                    Push.register(StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA), token)
                } catch (_: CoreException) {
                    // Registered again on the app's next start (Push.sync).
                }
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["type"] != "notice" || !shown(data["workspace"], data["kind"])) return
        val tag = data["tag"] ?: return
        val url = data["url"] ?: return
        val seq = data["seq"]?.toLongOrNull()
        Notifier.show(this, tag, data["title"].orEmpty(), data["body"].orEmpty(), url, seq)
        bring(data["workspace"], data["station"], data["session"], seq)
    }

    /**
     * What the push is about, onto the device while FCM lets the app run (`notice.bring`): tapped, its chat opens on it
     * instead of waiting for the station to be reached again. The app off screen was likely frozen, its connections gone
     * with nothing said: the core is told how long it was away first, as when it comes back to the front (MainActivity's
     * `wake`), since it went or since the push before woke it. Back on screen, it is still as long away as it was.
     */
    private fun bring(workspace: String?, station: String?, session: String?, seq: Long?) {
        if (workspace == null || station == null || session == null) return
        runBlocking {
            withTimeoutOrNull(BRING_MS) {
                try {
                    val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA)
                    val now = SystemClock.elapsedRealtime()
                    val since = hidden?.let { maxOf(it, woke ?: it) }
                    if (since != null) {
                        woke = now
                        core.call("client.wake", buildJsonObject { put("away", (now - since).coerceAtLeast(0)) })
                    }
                    core.call("notice.bring", buildJsonObject { put("station", "$workspace/$station"); put("session", session); seq?.let { put("seq", it) } })
                } catch (_: CoreException) {
                    // Not read now (the station not reached): the chat is read as it opens.
                }
            }
        }
    }

    /**
     * Whether the core has a push shown: not with notifications off, nor with the app in front (it shows its own), nor
     * of another workspace than the one the app is in, nor of a kind turned off (`notify.set` `kinds`).
     */
    private fun shown(workspace: String?, kind: String?): Boolean = runBlocking {
        withTimeoutOrNull(5_000) {
            try {
                val answer = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA).call("notice.pushed", buildJsonObject { workspace?.let { put("workspace", it) }; kind?.let { put("kind", it) } })
                (answer as? JsonObject)?.get("show")?.jsonPrimitive?.booleanOrNull
            } catch (_: CoreException) {
                null
            }
        } ?: !Notifier.inFront
    }
}
