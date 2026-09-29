package fail.still.android

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
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
import androidx.lifecycle.lifecycleScope
import fail.still.android.data.Auth
import fail.still.android.ui.StillFailTheme
import fail.still.android.ui.Loading
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.launch

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

    override fun onStart() {
        super.onStart()
        multicast?.acquire()
        app?.let { lifecycleScope.launch { it.checkUpdates() } }
    }

    override fun onStop() {
        multicast?.release()
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN)
            app = AppState(core, getSharedPreferences("stillfail", Context.MODE_PRIVATE), BuildConfig.CLOUD_ORIGIN, Updates(applicationContext, BuildConfig.CLOUD_ORIGIN))
            handle(intent)
            app?.checkUpdates()
        }
        setContent {
            val current = app
            val dark = when (current?.theme) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
            LaunchedEffect(dark) {
                val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                enableEdgeToEdge(bars, bars)
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
     * old host ember.3720.org) opens that item; a service's link (`?service=<job>`, from Slack) has the service over it.
     */
    private fun handle(intent: Intent?) {
        val uri = intent?.data ?: return
        val app = app ?: return
        val parts = uri.pathSegments
        if (uri.scheme == "https" && parts.size == 4 && parts[0] == "o") {
            setIntent(Intent())
            app.openItem(parts[1], parts[2], parts[3], uri.getQueryParameter("service")?.takeIf { it.isNotEmpty() })
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
