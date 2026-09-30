package fail.still.android

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.lifecycleScope
import fail.still.android.data.Auth
import fail.still.android.ui.StillFailTheme
import fail.still.android.ui.Loading
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class MainActivity : ComponentActivity() {
    private var app by mutableStateOf<AppState?>(null)

    /**
     * Android drops the multicast that reaches the phone unless an app holds this: the core's mDNS would never hear a
     * station on the LAN answer. Held while the app is on screen (it costs battery), as that is when it connects.
     */
    private val multicast: WifiManager.MulticastLock? by lazy {
        (applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
            ?.createMulticastLock("stillfail-mdns")?.apply { setReferenceCounted(false) }
    }

    /** The default network as it changes, told to the core (see [NetworkWatch]); registered while the activity lives. */
    private var network: NetworkWatch? = null

    /** The core's `notices`, shown while the app is in front (Notices.kt); FCM's pushes are shown the rest of the time. */
    private var notices: Job? = null

    private fun listen() {
        val app = app ?: return
        if (notices == null && Notifier.inFront) notices = lifecycleScope.launch { showNotices(applicationContext, app) }
    }

    override fun onStart() {
        super.onStart()
        multicast?.acquire()
        Notifier.inFront = true
        app?.inFront = true
        listen()
        app?.let { lifecycleScope.launch { it.checkUpdates() } }
        wake()
    }

    override fun onStop() {
        Notifier.inFront = false
        app?.inFront = false
        notices?.cancel()
        notices = null
        multicast?.release()
        if (hidden == null) hidden = SystemClock.elapsedRealtime()
        super.onStop()
    }

    override fun onDestroy() {
        network?.stop()
        network = null
        super.onDestroy()
    }

    /**
     * Back on screen after a while in the background, as the web page does on visibilitychange (web/src/core/client.ts
     * connectCore): the core gives up requests that went out before and reconnects links gone quiet
     * (client/core/src/wake.rs), so nothing hangs on a socket the system dropped while away.
     */
    private fun wake() {
        // No core yet (the activity made again, its core still starting): woken once it is there.
        val app = app ?: return
        val since = hidden ?: return
        hidden = null
        val away = (SystemClock.elapsedRealtime() - since).coerceAtLeast(0)
        lifecycleScope.launch {
            try {
                app.core.call("client.wake", buildJsonObject { put("away", away) })
            } catch (_: CoreException) {
                // An older core without it: nothing to wake.
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge to edge from the first frame (the theme's bars are set once it is known, below): else the first
        // composition is laid out inside the system bars and moves when they are taken away.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN)
            val made = AppState(core, getSharedPreferences("stillfail", Context.MODE_PRIVATE), BuildConfig.CLOUD_ORIGIN, Updates(applicationContext, BuildConfig.CLOUD_ORIGIN))
            // The notification settings the app kept, into the core before anything goes by them.
            made.moveNotify()
            made.inFront = Notifier.inFront
            app = made
            launch { made.followNotify() }
            handle(intent)
            listen()
            // Back to an activity made anew (the last one closed with back, the process kept): as back on screen.
            wake()
            network = NetworkWatch(applicationContext) {
                lifecycleScope.launch {
                    try {
                        core.call("client.wake", buildJsonObject { put("away", 0); put("network", true) })
                    } catch (_: CoreException) {
                    }
                }
            }.also { it.start() }
            launch { Push.sync(applicationContext, core) }
            app?.checkUpdates()
        }
        setContent {
            val current = app
            val dark = when (current?.theme) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
            LaunchedEffect(dark) {
                val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                enableEdgeToEdge(bars, bars)
                // The system's theme changes without the activity made again (configChanges uiMode): the window's own
                // ground follows it here, as the theme's resources would not.
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable((if (dark) fail.still.android.ui.Dark else fail.still.android.ui.Light).bg.toArgb()))
            }
            StillFailTheme(dark) {
                if (current == null) Loading("正在启动…")
                else CompositionLocalProvider(LocalApp provides current) { StillFailApp(current) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /**
     * still.fail cloud's sign-in comes back as stillfail://auth/callback?… (ember://, from before the rename, still
     * accepted), which the core finishes; an item's link (https://app.still.fail/o/<workspace>/<station>/<session>, or the
     * old host ember.3720.org) opens that item; a service's link (`?service=<job>`, from Slack) has the service over it;
     * an invitation's link and a chat's reference link go as links tapped in the app (AppState.openLink).
     */
    private fun handle(intent: Intent?) {
        val uri = intent?.data ?: return
        val app = app ?: return
        val parts = uri.pathSegments
        // http too: a notification opens its chat on a dev cloud's origin (Notifier.show).
        if ((uri.scheme == "https" || uri.scheme == "http") && parts.size == 4 && parts[0] == "o") {
            setIntent(Intent())
            app.openItem(parts[1], parts[2], parts[3], uri.getQueryParameter("service")?.takeIf { it.isNotEmpty() })
            return
        }
        // An invitation's link, or a link to a chat as chats refer to each other: as a link tapped in the app.
        if (uri.scheme == "https" && (parts == listOf("invite") || parts.firstOrNull() == "w")) {
            setIntent(Intent())
            app.openLink(uri.toString())
            return
        }
        if (uri.scheme !in AUTH_SCHEMES || uri.host != "auth") return
        setIntent(Intent())
        lifecycleScope.launch {
            try {
                Auth.complete(app.core, "?" + (uri.encodedQuery ?: ""))
                app.home()
            } catch (e: CoreException) {
                app.toast = "登录没有完成：${e.message}"
            }
        }
    }
}

/** The sign-in callback's schemes: stillfail:// is what the app asks for; ember:// (the name before) is still accepted. */
private val AUTH_SCHEMES = setOf("stillfail", "ember")

/**
 * Since when the app has been off screen (elapsedRealtime: it counts deep sleep too); null while on it. The process's,
 * not an activity's: one closed with back and made again later is the same app coming back to the same core.
 */
private var hidden: Long? = null

/**
 * The default network, followed: `changed` when it becomes another one than before (Wi-Fi to mobile data, back
 * online after none). Every connection the core has was on the old one and is dead with nothing said; iroh cannot
 * see this on Android itself (client/core/src/wake.rs, mesh.rs `watch`). The first network seen is the one the core
 * started on, so nothing is said of it.
 */
private class NetworkWatch(context: Context, private val changed: () -> Unit) : ConnectivityManager.NetworkCallback() {
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    private var current: Network? = null
    private var seen = false

    fun start() {
        try {
            connectivity?.registerDefaultNetworkCallback(this)
        } catch (_: RuntimeException) {
            // Too many callbacks registered (the system's limit), or no permission: the wake on coming back still is.
        }
    }

    fun stop() {
        try {
            connectivity?.unregisterNetworkCallback(this)
        } catch (_: RuntimeException) {
        }
    }

    override fun onAvailable(network: Network) {
        val before = synchronized(this) {
            val before = current to seen
            current = network
            seen = true
            before
        }
        if (before.second && before.first != network) changed()
    }

    override fun onLost(network: Network) {
        synchronized(this) { if (current == network) current = null }
    }
}
