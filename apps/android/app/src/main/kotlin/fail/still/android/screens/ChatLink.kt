// Copying a chat's link, to paste into another chat for its agent to read (web chatRefs.ts shareLink, copyChatLink):
// from its row's menu (Home.kt rowMenu) and from its own sheet (ChatInfo.kt).
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.TextUtils
import fail.still.android.AppState
import fail.still.android.data.t
import java.net.URLEncoder

/**
 * A chat's still.fail link, `<cloud>/o/<workspace>/<station>/<session>`, as web's shareLink makes it. Null for a station
 * of no workspace (no `/` in its address) or a chat its station has not given a session yet: neither has one.
 */
internal fun chatLink(cloud: String, station: String, session: String): String? {
    val at = station.indexOf('/')
    if (at <= 0 || at == station.length - 1 || session.isEmpty()) return null
    return "${cloud.trimEnd('/')}/o/${station.substring(0, at)}/${station.substring(at + 1)}/${encodeComponent(session)}"
}

/** As JavaScript's encodeURIComponent (what web's link has): URLEncoder's form encoding, put back where the two differ. */
internal fun encodeComponent(s: String): String = URLEncoder.encode(s, "UTF-8")
    .replace("+", "%20").replace("%21", "!").replace("%27", "'").replace("%28", "(").replace("%29", ")").replace("%7E", "~")

/** What goes on the clipboard as text: `[title](link)`, as a reference is sent; the title kept to a line of 120 at most. */
internal fun chatLinkText(title: String, link: String): Pair<String, String> {
    val whole = title.replace(Regex("[\\[\\]\n]"), " ").trim().ifEmpty { link }
    val shown = if (whole.codePointCount(0, whole.length) > 120) whole.substring(0, whole.offsetByCodePoints(0, 120)) else whole
    return shown to "[$shown]($link)"
}

/**
 * Puts a chat's link on the clipboard: `[title](link)` for plain text (a composer, where it becomes a reference again,
 * or a terminal), and a link for what takes HTML (Slack, documents). A toast says it is copied, or why not.
 */
fun copyChatLink(app: AppState, context: Context, title: String, link: String) {
    val (shown, plain) = chatLinkText(title, link)
    try {
        val html = "<a href=\"${TextUtils.htmlEncode(link)}\">${TextUtils.htmlEncode(shown)}</a>"
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newHtmlText("still.fail", plain, html))
        app.toast = t("web-main.chat.linkCopied")
    } catch (e: Exception) {
        app.toast = t("web-main.chat.copyFailed", "error" to (e.message ?: e.toString()))
    }
}
