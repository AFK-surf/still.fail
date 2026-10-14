// A chat made public (docs/public-share.md; the core's views/publish.ts), from its sheet (ChatInfo.kt): its links, and
// the sheet that publishes it (web mobile/Chat.tsx PublishList / PublishSheet).
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.ChatPublish
import fail.still.android.data.ChatPublished
import fail.still.android.data.PublishMessage
import fail.still.android.data.PublishFile
import fail.still.android.data.PublishPreview
import fail.still.android.data.errorText
import fail.still.android.data.t
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Markdown
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.core.CoreException

/** A chat's public links as its sheet shows them: to those who may publish it, or when it has some (a read-only member sees them). */
internal fun shownPublish(publish: ChatPublish?): ChatPublish? = publish?.takeIf { it.may || it.links.isNotEmpty() }

/**
 * Making the chat public, a card of its own in its sheet: 「公开分享」 opens the sheet that publishes it, for those who
 * may (not a read-only member); each of its links under it, when and by whom, 复制, and 撤销 for who published it or an
 * owner or admin (asked first; gone from here at once).
 */
@Composable
internal fun PublishList(app: AppState, station: String, thread: Long, publish: ChatPublish) {
    InfoList {
        if (publish.may) InfoRow(onClick = { openPublish(app, station, thread) }) {
            IconIn(Icons.Web, 16.dp, C.ink)
            Text(t("web-pages.chat.publish"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
            IconIn(Icons.ChevronRight, 14.dp, C.subtle)
        }
        publish.links.forEach { l -> PublishedRow(app, station, thread, l) }
    }
}

@Composable
private fun PublishedRow(app: AppState, station: String, thread: Long, link: ChatPublished) {
    val context = LocalContext.current
    InfoRow {
        Text(listOfNotNull(link.time?.get("createdAt")?.ago, link.byName).joinToString(" · "), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        TextAction(t("common.copy")) { copyLink(app, context, link.link) }
        if (link.mayRevoke) TextAction(t("web-pages.chat.publish.revoke")) {
            confirm(app, t("web-pages.chat.publish.revokeAsk"), t("web-pages.chat.publish.revokeNote"), t("web-pages.chat.publish.revoke"), danger = true, what = t("web-pages.chat.publish.revokeVerb")) {
                app.api(station).unpublish(thread, link.id)
            }
        }
    }
}

/** A link's words as a button (in the accent, no frame), as the phone's web draws one (parts.tsx LinkButton). */
@Composable
private fun TextAction(label: String, onClick: () -> Unit) {
    Text(label, fontSize = 14.sp, color = C.accent, modifier = Modifier.clip(Smooth(6.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 2.dp))
}

/** Puts a link on the clipboard, saying so. */
private fun copyLink(app: AppState, context: Context, link: String) {
    try {
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", link))
        app.toast = t("common.link.copied")
    } catch (e: Exception) {
        app.toast = t("common.link.copyFailed", "error" to (e.message ?: e.toString()))
    }
}

/** A preview as asked (`chat.publishPreview`): being read, read, or why not. */
private sealed interface Previewed {
    data object Reading : Previewed
    data class Ok(val preview: PublishPreview) : Previewed
    data class Failed(val error: String) : Previewed
}

/**
 * Publishes the chat (web mobile/Chat.tsx PublishSheet): what it would hold, asked as the sheet opens; the attachments
 * to tick (all at first; one too big is shown, never ticked), who can read it, 「发布」. Published, its link with a way
 * to copy it; the chat's sheet lists it from then on.
 */
internal fun openPublish(app: AppState, station: String, thread: Long) {
    app.sheet = SheetSpec(0.9f) {
        val context = LocalContext.current
        var shown by remember { mutableStateOf<Previewed>(Previewed.Reading) }
        var off by remember { mutableStateOf(emptySet<String>()) }
        var made by remember { mutableStateOf<ChatPublished?>(null) }
        LaunchedEffect(thread) {
            shown = try { Previewed.Ok(app.api(station).publishPreview(thread)) } catch (e: CoreException) { Previewed.Failed(errorText(e)) }
        }
        val publishing = app.isDoing("chat.publish", "station" to station, "thread" to thread)
        SheetGrab()
        SheetHead(if (made != null) t("web-pages.chat.publish.made") else t("web-pages.chat.publish"))
        // Its words 20dp in from the edges; the attachments' rows run to them, as a list to tick does.
        val inset = Modifier.padding(horizontal = 20.dp)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("web-pages.chat.publish.lead"), fontSize = 12.sp, color = C.muted, modifier = inset)
            val now = shown
            val done = made
            when {
                done != null -> {
                    Text(done.link, fontSize = 14.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = inset.fillMaxWidth().clip(Smooth(22.dp)).background(C.ink.copy(alpha = 0.04f)).padding(horizontal = 14.dp, vertical = 10.dp))
                    Row(inset.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Button(t("common.done"), primary = false) { app.sheet = null }
                        Button(t("common.link.copy"), primary = true) { copyLink(app, context, done.link) }
                    }
                }
                now is Previewed.Reading -> Row(inset, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Spinner(14.dp)
                    Text(t("web-pages.chat.publish.reading"), fontSize = 14.sp, color = C.muted)
                }
                now is Previewed.Failed -> Text(now.error, fontSize = 13.sp, color = C.red, modifier = inset)
                now is Previewed.Ok && now.preview.messages.isEmpty() -> Text(t("web-pages.chat.publish.empty"), fontSize = 14.sp, color = C.muted, modifier = inset)
                now is Previewed.Ok -> {
                    val p = now.preview
                    val ticked = p.files.filter { !it.over && it.k !in off }
                    val over = ticked.fold(0UL) { n, f -> n + f.size } > p.most
                    // As the chat draws others' messages, on a card.
                    Column(inset.fillMaxWidth().clip(Smooth(22.dp)).background(C.ink.copy(alpha = 0.04f)).padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        p.messages.forEach { m -> PreviewMessage(m, off) { k -> off = if (k in off) off - k else off + k } }
                    }
                    p.hiddenText?.let { Text(it, fontSize = 12.sp, color = C.muted, modifier = inset) }
                    if (over) Text(t("web-pages.chat.publish.overTotal", "most" to p.mostText), fontSize = 13.sp, color = C.red, modifier = inset)
                    Row(inset.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(t("web-pages.chat.publish.go"), primary = true, busy = publishing, enabled = !over) {
                            app.act(t("web-pages.chat.publish.verb")) { made = app.api(station).publish(thread, p.upto, ticked.map { it.k }) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * A message as the snapshot would hold it, drawn as the chat draws someone else's (Chat.kt SaidRow): its avatar and
 * name in line over what it says, an agent's in Markdown; under it its attachments, each ticked to go with it or not
 * (`off`: those left out), and with something hidden, how many.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PreviewMessage(m: PublishMessage, off: Set<String>, toggle: (String) -> Unit) {
    val ink = chatInk()
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.padding(top = 3.dp)) { if (m.agent) AgentAvatar(null, null) else Avatar(m.author, m.author, 18.dp) }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.padding(start = 25.dp).heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(m.author, fontSize = 15.sp, fontWeight = FontWeight(650), color = ink.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 240.dp))
                MessageTime(m.time?.get("createdAt"))
            }
            if (m.agent) Markdown(m.text)
            else if (m.text.isNotEmpty()) Text(fail.still.android.ui.withRefs(m.text), fontSize = 15.sp, lineHeight = 23.sp, color = ink.text)
            if (m.files.isNotEmpty()) FlowRow(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                m.files.forEach { f -> FileToggle(f, on = !f.over && f.k !in off) { toggle(f.k) } }
            }
            m.hiddenText?.let { hidden ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    IconIn(Icons.ShieldCheck, 13.dp, C.muted)
                    Text(hidden, fontSize = 12.sp, color = C.muted)
                }
            }
        }
    }
}

/** An attachment in the preview (web Publish.tsx FileToggle): ticked, it goes with the snapshot; unticked, greyed; one too big never goes. */
@Composable
private fun FileToggle(f: PublishFile, on: Boolean, toggle: () -> Unit) {
    Row(
        Modifier.clip(Smooth(12.dp)).background(C.ink.copy(alpha = 0.05f)).clickable(enabled = !f.over, onClick = toggle)
            .heightIn(min = 32.dp).padding(start = 8.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // The app's checkbox (web global.css.ts): a soft square, ink with a check when ticked.
        Box(
            Modifier.size(18.dp).clip(Smooth(6.dp)).background(if (on) C.ink else C.bg)
                .border(1.dp, if (on) C.ink else C.line, Smooth(6.dp)).alpha(if (f.over) 0.45f else 1f),
            contentAlignment = Alignment.Center,
        ) { if (on) IconIn(Icons.Check, 12.dp, C.bg) }
        Text(f.name, fontSize = 13.sp, color = if (on) C.ink else C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 200.dp))
        Text(if (f.over) t("web-pages.chat.publish.tooBig") else f.sizeText, fontSize = 13.sp, color = if (on) C.muted else C.subtle)
    }
}
