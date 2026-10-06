// The words people read, in their language: the same catalog the core and the web app read
// (client/i18n/catalog/<lang>/*.json, packaged as the app's assets; client/i18n/src/lib.rs says how). Which language is
// the core's (prefs `lang`: as chosen, else as the phone is); before the core answers, or with a core from before
// languages, the phone's. `lang` is state: what reads words while it is drawn is drawn again when it changes.
package fail.still.android.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.util.Locale

object I18n {
    private var words: Map<String, Map<String, Any>> = emptyMap()

    /** `zh` or `en`. */
    var lang by mutableStateOf(langOf(Locale.getDefault().toLanguageTag()))

    /** Chinese for Chinese, English for any other; Chinese when nothing is said (as the core decides). */
    fun langOf(locale: String?): String = locale.orEmpty().trim().lowercase().let { if (it.isEmpty() || it.startsWith("zh")) "zh" else "en" }

    /** Reads the catalog from the app's assets, once at start. */
    fun load(context: Context) {
        if (words.isNotEmpty()) return
        words = listOf("zh", "en").associateWith { lang ->
            val all = mutableMapOf<String, Any>()
            for (file in context.assets.list(lang).orEmpty().filter { it.endsWith(".json") }.sorted()) {
                val text = context.assets.open("$lang/$file").bufferedReader().use { it.readText() }
                for ((key, value) in Json.parseToJsonElement(text) as JsonObject) {
                    all[key] = when (value) {
                        is JsonPrimitive -> value.content
                        is JsonObject -> value.mapValues { it.value.jsonPrimitive.contentOrNull.orEmpty() }
                        else -> continue
                    }
                }
            }
            all
        }
    }

    /** Follows the core's prefs: `lang` as it says, else the phone's. */
    fun follow(said: String?) {
        lang = if (said == "zh" || said == "en") said else langOf(Locale.getDefault().toLanguageTag())
    }

    /** The words for `key` in a language, with `args` put in for `{name}`; `n` chooses between `one` and `other`. */
    fun tr(language: String, key: String, args: Map<String, Any?> = emptyMap()): String {
        val found = words[language]?.get(key) ?: words["zh"]?.get(key)
        val text = when (found) {
            is String -> found
            is Map<*, *> -> ((if (args["n"]?.toString() == "1") found["one"] else null) ?: found["other"]) as? String ?: key
            else -> key
        }
        if (args.isEmpty()) return text
        return Regex("""\{(\w+)\}""").replace(text) { m -> if (args.containsKey(m.groupValues[1])) args[m.groupValues[1]].toString() else m.value }
    }
}

/** The words for `key` in the language now: `t("chat.send")`, `t("chats.count", "n" to 3)`. */
fun t(key: String, vararg args: Pair<String, Any?>): String = I18n.tr(I18n.lang, key, args.toMap())
