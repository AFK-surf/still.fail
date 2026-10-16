// A station's screen, seen and driven (docs/remote-screens.md): an activity of its own over the app, full screen, in
// either orientation, opened from a screen's link (`link.parse` → `screen`: App Links, links in chats) and from the
// station's page (screens/Stations.kt). The view is open while it is in sight, and let go when it is not: coming back,
// it opens again from the frame it showed. Turning the phone keeps the activity (configChanges): the view goes on.
package fail.still.android.remote

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.IntSize
import androidx.lifecycle.lifecycleScope
import fail.still.android.BuildConfig
import fail.still.android.data.I18n
import fail.still.android.data.Prefs
import fail.still.android.data.PrefsView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.t
import fail.still.android.ui.Dark
import fail.still.android.ui.Light
import fail.still.android.ui.Loading
import fail.still.android.ui.StillFailTheme
import fail.still.core.StillFailCore
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull

class ScreenActivity : ComponentActivity() {
    companion object {
        private const val STATION = "station"
        private const val SCREEN = "screen"
        private const val TITLE = "title"

        /** Opens the viewer on `screen` of `station` (its address, `<workspace>/<station>`); `title` until the core says one. */
        fun open(context: Context, station: String, screen: String, title: String? = null) {
            context.startActivity(
                Intent(context, ScreenActivity::class.java).putExtra(STATION, station).putExtra(SCREEN, screen).putExtra(TITLE, title),
            )
        }

        /** The largest frame worth asking for: this phone's screen, its longer side first, at most 1920×1080. */
        fun limit(context: Context): IntSize {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val (w, h) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) wm.maximumWindowMetrics.bounds.let { it.width() to it.height() }
            else context.resources.displayMetrics.let { it.widthPixels to it.heightPixels }
            return IntSize(minOf(maxOf(w, h), 1920), minOf(minOf(w, h), 1080))
        }
    }

    private var session by mutableStateOf<ScreenSession?>(null)
    /** 外观 as the core keeps it ("system", "light", "dark"). */
    private var appearance by mutableStateOf("system")

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // While it is looked at, the phone stays awake: a screen is watched more than touched.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        I18n.load(applicationContext)
        val station = intent.getStringExtra(STATION)
        val screen = intent.getStringExtra(SCREEN)
        val title = intent.getStringExtra(TITLE)
        if (station == null || screen == null) { finish(); return }
        lifecycleScope.launch {
            // The app's core (started already, unless the system brought this activity back alone).
            val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA)
            val prefs = Prefs.first(core)
            I18n.follow(prefs.lang)
            appearance = prefs.appearance ?: "system"
            val made = ScreenSession(core, station, screen, lifecycleScope, limit(this@ScreenActivity))
            session = made
            if (lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) made.open()
            // The theme and the language, followed as they change.
            core.topic(Topics.prefs).collect { state ->
                val value = state.value?.takeIf { it !is JsonNull }?.let { runCatching { decode(PrefsView.serializer(), it) }.getOrNull() } ?: return@collect
                appearance = value.appearance ?: "system"
                I18n.follow(value.lang)
            }
        }
        setContent {
            val dark = when (appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
            LaunchedEffect(dark) {
                val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                enableEdgeToEdge(bars, bars)
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable((if (dark) Dark else Light).bg.toArgb()))
            }
            StillFailTheme(dark) {
                val current = session
                if (current == null) Loading(t("android-misc.screen.connecting"))
                else ScreenViewer(current, title, ::finish)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        session?.open()
    }

    override fun onStop() {
        session?.pause()
        super.onStop()
    }

    override fun onDestroy() {
        session?.close()
        super.onDestroy()
    }
}
