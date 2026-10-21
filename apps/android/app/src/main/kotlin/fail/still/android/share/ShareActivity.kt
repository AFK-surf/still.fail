// What another app shares into still.fail (docs/share-in.md): the system's share sheet hands this activity a link or
// some text (ACTION_SEND, text/plain), and it shows over that app, not over still.fail: one sheet of the chats it can
// go to. A tap puts what is shared in that chat's composer and opens still.fail at the chat (MainActivity, by
// `OPEN_STATION` / `OPEN_SESSION`), where it is added to and sent; this activity ends.
package fail.still.android.share

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import fail.still.android.BuildConfig
import fail.still.android.MainActivity
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.I18n
import fail.still.android.data.Prefs
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.entries
import fail.still.android.ui.StillFailTheme
import fail.still.core.StillFailCore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray

/** What is shared: its text as the core takes it (`source`), and the subject the app gave with it. */
data class Shared(val source: String, val title: String?)

/** Where to send it: the core, and the workspace it goes to (the one last open in the app); null workspace: none yet. */
class ShareTarget(val core: StillFailCore, val workspace: String?)

class ShareActivity : ComponentActivity() {
    private var target by mutableStateOf<ShareTarget?>(null)
    private var appearance by mutableStateOf("system")
    private var faces by mutableStateOf<fail.still.android.data.FontsView?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        fail.still.android.ui.Motion.install(applicationContext)
        I18n.load(applicationContext)
        fail.still.android.ui.FaceFiles.init(applicationContext)
        val shared = sharedOf(intent)
        if (shared == null) { finish(); return }
        lifecycleScope.launch {
            // The app's core (started already when the app runs; else started here, as the screen viewer's is).
            val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA)
            val prefs = Prefs.first(core)
            I18n.follow(prefs.lang)
            appearance = prefs.appearance ?: "system"
            faces = prefs.faces
            fail.still.android.ui.Motion.chosen = prefs.motion
            // The workspace last open, else the first one the accounts have (none signed in: none).
            val workspace = prefs.workspace ?: run {
                val accounts = core.topic(Topics.accounts).first { it.value != null }.value as? JsonArray
                if (accounts.isNullOrEmpty()) null
                else core.topic(Topics.workspaces).first { it.value != null }.value?.let { v ->
                    runCatching { decode(ListSerializer(AccountWorkspaces.serializer()), v).entries().firstOrNull()?.workspace?.id }.getOrNull()
                }
            }
            target = ShareTarget(core, workspace)
        }
        setContent {
            val dark = when (appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
            StillFailTheme(dark, fail.still.android.ui.rememberFonts(faces)) {
                ShareScreen(shared, target, onOpen = { openApp(it) }, onOpenApp = { openApp(null) }, onClose = ::finish)
            }
        }
    }

    /** still.fail itself: at a chat (`to`: its session, or a new chat on its station), or as it was. */
    private fun openApp(to: Opened?) {
        val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (to != null) {
            // The app may have that chat's composer open already (its process kept): it takes what the core put in it.
            to.key?.let { fail.still.android.screens.Drafts.refresh(it) }
            open.putExtra(MainActivity.OPEN_STATION, to.station)
            to.session?.let { open.putExtra(MainActivity.OPEN_SESSION, it) }
        }
        startActivity(open)
        finish()
    }

    override fun finish() {
        super.finish()
        // The sheet went with its own motion: no other on top of it.
        @Suppress("DEPRECATION") overridePendingTransition(0, 0)
    }

    companion object {
        /** What a share intent carries: its text (a link, as browsers and video apps share it), its subject; null if none. */
        fun sharedOf(intent: Intent?): Shared? {
            if (intent?.action != Intent.ACTION_SEND) return null
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
            if (text.isEmpty()) return null
            val title = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()?.takeIf { it.isNotEmpty() && it != text }
            return Shared(text, title)
        }

    }
}
