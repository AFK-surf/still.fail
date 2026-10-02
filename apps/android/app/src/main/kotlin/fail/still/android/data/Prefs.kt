// How its person likes it on this device, as the core keeps it (its `prefs` topic, `prefs.set`; client/core/src/prefs.rs),
// as web/src/prefs.ts has it: the workspace last open, the appearance, whose pictures lead a row, 只看我的, a new connect
// to go on with. The app kept these in its preferences before; they go into the core once (AppState reads the core's).
package fail.still.android.data

import android.content.SharedPreferences
import android.os.Build
import fail.still.android.BuildConfig
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object Prefs {
    private const val RESUME = "newConnect.resume/"

    /** What the app kept itself before the core did: into the core, only what it has not been told, then gone from here. */
    suspend fun moveIn(core: StillFailCore, prefs: SharedPreferences) {
        val resume = prefs.all.keys.filter { it.startsWith(RESUME) }
        val old = listOf("workspace", "theme", "rowPicture", "onlyMine").filter(prefs::contains) + resume
        if (old.isEmpty()) return
        val patch = buildJsonObject {
            put("fill", true)
            prefs.getString("workspace", null)?.let { put("workspace", it) }
            prefs.getString("theme", null)?.takeIf { it in setOf("system", "light", "dark") }?.let { put("appearance", it) }
            prefs.getString("rowPicture", null)?.takeIf { it in setOf("auto", "agents", "people") }?.let { put("rowPicture", it) }
            if (prefs.contains("onlyMine")) put("onlyMine", prefs.getBoolean("onlyMine", false))
            val made = resume.mapNotNull { key -> prefs.getString(key, null)?.split('\u0000')?.firstOrNull { it.isNotEmpty() }?.let { key.removePrefix(RESUME) to it } }
            if (made.isNotEmpty()) put("resume", buildJsonObject { made.forEach { (station, app) -> put(station, app) } })
        }
        try {
            core.call("prefs.set", patch)
            prefs.edit().apply { old.forEach(::remove) }.apply()
        } catch (_: CoreException) {
            // Tried again on the next start; they stay here until then.
        }
    }

    /** Tells the core what this device is, once at start: it decides what follows (the name it signs in as, the app a message is sent from). */
    suspend fun tellDevice(core: StillFailCore) {
        try {
            core.call("client.device", buildJsonObject { put("app", "android"); put("build", BuildConfig.VERSION_NAME); put("model", "${Build.MANUFACTURER} ${Build.MODEL}"); put("locale", java.util.Locale.getDefault().toLanguageTag()) })
        } catch (_: CoreException) {
        }
    }

    /** The core's first value (it is on the device: at once), for the first frame to be as they are. */
    suspend fun first(core: StillFailCore): PrefsView =
        core.topic(Topics.prefs).first { it.value != null || it.error != null }.value?.takeIf { it !is JsonNull }
            ?.let { runCatching { decode(PrefsView.serializer(), it) }.getOrNull() } ?: PrefsView()
}
