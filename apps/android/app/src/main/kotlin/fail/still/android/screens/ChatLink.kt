// Copying a chat's link, to paste into another chat for its agent to read (web chatRefs.ts shareLink, copyChatLink):
// from its row's menu (Home.kt rowMenu) and from its own sheet (ChatInfo.kt).
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.TextUtils
import fail.still.android.AppState
import fail.still.android.data.t
import java.net.URLDecoder
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

/** A chat a link names (web chatRefs.ts chatOfLink): its station (`<workspace>/<station>`), its key, and `?history=…` after it, or "". */
internal data class LinkedChat(val station: String, val id: String, val history: String)

private val SHARED = Regex("/o/([^/?#\\s]+)/([^/?#\\s]+)/([^/?#\\s]+)/?(\\?history=[^&#\\s]+(?:&entry=\\d+)?)?$")
private val PAGE = Regex("/w/([^/?#\\s]+)/s/([^/?#\\s]+)/chats/([^/?#\\s]+)/?(\\?history=[^&#\\s]+(?:&entry=\\d+)?)?$")

/** The chat a link names: a still.fail link (`…/o/<workspace>/<station>/<session>`) or its page (`…/w/<workspace>/s/<station>/chats/<id>`); null otherwise. */
internal fun chatOfLink(href: String): LinkedChat? {
    val m = SHARED.find(href) ?: PAGE.find(href) ?: return null
    val id = try { URLDecoder.decode(m.groupValues[3].replace("+", "%2B"), "UTF-8") } catch (_: IllegalArgumentException) { return null }
    return LinkedChat("${m.groupValues[1]}/${m.groupValues[2]}", id, m.groupValues[4])
}

private val PASTED_REF = Regex("\\[([^\\]\\n]{1,120})\\]\\((\\S+?)\\)")

/**
 * The chats' links in `text`, `[its title](its link)` as one is copied (copyChatLink), of the workspace of `here` (the
 * station written on; one of no workspace has none), as web's composer takes them when pasted (Chat.tsx pasteReferences).
 */
internal fun linkedRefs(text: String, here: String): List<Pair<MatchResult, LinkedChat>> {
    if (!here.contains('/')) return emptyList()
    val workspace = here.substringBefore('/')
    return PASTED_REF.findAll(text).mapNotNull { m -> chatOfLink(m.groupValues[2])?.takeIf { it.station.substringBefore('/') == workspace }?.let { m to it } }.toList()
}

/** Where one change put text in (a paste): the range in `now` that is not in `was`; null when nothing went in. */
internal fun insertedRange(was: String, now: String): IntRange? {
    val most = minOf(was.length, now.length)
    var start = 0
    while (start < most && was[start] == now[start]) start++
    var end = 0
    while (end < most - start && was[was.length - 1 - end] == now[now.length - 1 - end]) end++
    return if (now.length - end > start) start until now.length - end else null
}

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
