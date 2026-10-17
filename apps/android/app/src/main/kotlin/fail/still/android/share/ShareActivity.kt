// What another app shares into still.fail (docs/share-in.md): the system's share sheet hands this activity a link or
// some text (ACTION_SEND, text/plain), and it shows over that app, not over still.fail: one sheet of the chats it can
// go to, the composer under them. Sent, the sheet goes and only a note is left at the foot of the screen (its window
// shrunk to it, touches beside it going to the app under it), with 打开; then the activity ends, and the app it came
// from is as it was.
package fail.still.android.share

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
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

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        I18n.load(applicationContext)
        val shared = sharedOf(intent)
        if (shared == null) { finish(); return }
        lifecycleScope.launch {
            // The app's core (started already when the app runs; else started here, as the screen viewer's is).
            val core = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA)
            val prefs = Prefs.first(core)
            I18n.follow(prefs.lang)
            appearance = prefs.appearance ?: "system"
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
            StillFailTheme(dark) {
                ShareScreen(shared, target, onSent = ::sent, onOpenApp = ::openApp, onClose = ::finish)
            }
        }
    }

    /**
     * Sent: the window only as tall as the note at its foot (`height` px; a window of WRAP_CONTENT stays the screen's,
     * as what is in it fills its parent), and what is beside it the app's under it.
     */
    private fun sent(height: Int) {
        if (window.attributes.height == height) return
        // The keyboard (gone with the sheet) no longer moves what is left.
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING or WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, height)
        window.setGravity(Gravity.BOTTOM)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
    }

    /** still.fail itself: at a chat (`link`, as an item's link opens it), or as it was. */
    private fun openApp(link: String?) {
        val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (link != null) open.setAction(Intent.ACTION_VIEW).setData(Uri.parse(link))
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

        /** An item's link, as Slack's open the app at it (MainActivity.handle → link.parse). */
        fun itemLink(station: String, session: String): String {
            val (ws, st) = station.split('/', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            return "${BuildConfig.CLOUD_ORIGIN.trimEnd('/')}/o/${Uri.encode(ws)}/${Uri.encode(st)}/${Uri.encode(session)}"
        }
    }
}
