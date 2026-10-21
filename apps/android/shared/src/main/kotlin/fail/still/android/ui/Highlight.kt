// Code blocks coloured as the web colours them: vitesse-light and vitesse-dark, Shiki's themes the web drew code in.
// What each piece of code is comes from the core (`code.ink`, client/core-ts/src/highlight.ts): its `ink`, runs of a
// scope's letter and a length; here each scope only takes the theme's colour for it. Dark takes each light colour's
// vitesse-dark twin ([DARK], the pairs Shiki gives the same tokens).
package fail.still.android.ui

import android.util.LruCache
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import fail.still.core.StillFailCore
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** vitesse-light's colours (its tokenColors), by the letter `ink` writes for what they colour (highlight.ts SCOPES). */
private val LIGHT = listOf(
    Color(0xFF393A34), // a text
    Color(0xFFA0ADA0), // b comment
    Color(0xFF999999), // c punctuation
    Color(0xFFB56959), // d string
    Color(0x77B56959), // e a string's quotes
    Color(0xFF2F798A), // f number
    Color(0xFF1E754F), // g keyword, keyword.control, constant.language (true, None), entity.name.tag
    Color(0xFFAB5959), // h storage (function, const, class), keyword.operator, null, undefined
    Color(0xFF59873A), // i function
    Color(0xFFB07D48), // j variable
    Color(0xFFA65E2B), // k constant, variable.language (this, self), an option (-x)
    Color(0xFF2E8F82), // l type
    Color(0xFF998418), // m property names, support (builtins as print, echo)
    Color(0x77998418), // n a property's quotes
    Color(0xFF22863A), // o a diff's line added
    Color(0xFFB31D28), // p a diff's line removed
    Color(0xFF6F42C1), // q a hunk's range
)

/** vitesse-dark's colour for each of vitesse-light's (Shiki's `--shiki-dark` beside the light colour, same token). */
private val DARK = listOf(
    Color(0xEEDBD7CA), Color(0xDD758575), Color(0xFF666666), Color(0xFFC98A7D), Color(0x77C98A7D), Color(0xFF4C9A91),
    Color(0xFF4D9375), Color(0xFFCB7676), Color(0xFF80A665), Color(0xFFBD976A), Color(0xFFC99076), Color(0xFF5DA994),
    Color(0xFFB8A965), Color(0x77B8A965), Color(0xFF85E89D), Color(0xFFFDAEB7), Color(0xFFB392F0),
)

/** `code` in its theme's colours as its `ink` has them; plain (null ink) in the text colour. */
fun paint(code: String, ink: String?, dark: Boolean): AnnotatedString {
    val colours = if (dark) DARK else LIGHT
    if (ink == null) return AnnotatedString(code)
    val spans = ArrayList<AnnotatedString.Range<SpanStyle>>()
    var at = 0
    var i = 0
    while (i < ink.length && at < code.length) {
        val scope = ink[i] - 'a'
        i++
        var length = 0
        while (i < ink.length && ink[i].isDigit()) { length = length * 10 + (ink[i] - '0'); i++ }
        val end = minOf(code.length, at + if (length == 0) 1 else length)
        colours.getOrNull(scope)?.let { spans += AnnotatedString.Range(SpanStyle(color = it), at, end) }
        at = end
    }
    if (at < code.length) spans += AnnotatedString.Range(SpanStyle(color = colours[0]), at, code.length)
    return AnnotatedString(code, spans)
}

/** The `ink` the core gave of code, by its language and the code (null: it shows as it is). Bound by characters. */
private data class InkOf(val code: String, val language: String)
private val inks = object : LruCache<InkOf, KnownInk>(512 * 1024) {
    override fun sizeOf(key: InkOf, value: KnownInk) = key.code.length.coerceAtLeast(1)
}

/** What the core said of some code: its `ink`, or null where it shows as it is. */
class KnownInk(val ink: String?)

/** What the core said of `code` already, else null (not asked yet); none to ask of code with no language. */
fun inkKnown(code: String, language: String?): KnownInk? = if (language == null) KnownInk(null) else inks.get(InkOf(code, language.lowercase()))

/** The colours of `code` in `language`, the core's (`code.ink`); null when it shows as it is or the core cannot say. */
suspend fun inkOf(core: StillFailCore, code: String, language: String?): String? {
    val lang = language?.lowercase() ?: return null
    inks.get(InkOf(code, lang))?.let { return it.ink }
    val ink = try {
        core.call("code.ink", buildJsonObject { put("code", code); put("lang", lang) }).jsonObject["ink"]?.jsonPrimitive?.contentOrNull
    } catch (_: Exception) {
        return null
    }
    inks.put(InkOf(code, lang), KnownInk(ink))
    return ink
}
