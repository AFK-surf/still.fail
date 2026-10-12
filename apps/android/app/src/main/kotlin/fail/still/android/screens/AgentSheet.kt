// An agent of the chat in brief: a sheet over the chat, opened from its name beside its messages, its mark in the
// chat's bar or its row in the chat's own sheet (web mobile/AgentSheet.tsx; the wide screen's card over its avatar,
// web AgentCard.tsx). What it runs and where it stands (with a stop while it works), its latest lines, the figures
// that say most (the core's `agentCard` view, client/core-ts/src/views/brief.ts), then where to go on: its account
// (how it runs), its history, its jobs. Only what is worth a look is coloured. The same parts head its history's
// details (History.kt).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.Screen
import fail.still.android.data.AgentCardView
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ModelMark
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetSpec
import kotlinx.coroutines.delay

private val ChatAgent.working get() = status == "running" || status == "queued"

/** Opens `agent`'s card over its chat, as tall as what it shows (its lines' and figures' room kept while they are read). */
fun openAgent(app: AppState, station: String, of: ChatOf, agent: ChatAgent) {
    val key = agent.session.key
    val rows = 2 + if (agent.jobs.isNotEmpty()) 1 else 0
    // What is wrong, a line each but a quota's (its account's windows say that).
    val notes = agent.attention.count { it.kind != "quota" }
    val tall = 22 + 52 + (if (agent.turns.isNotEmpty()) 72 + 76 else 0) + (if (notes > 0) 8 + notes * 20 else 0) + 12 + rows * 40 + 24
    app.sheet = SheetSpec(0.55f, fit = tall.dp) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val card by rememberTopic<AgentCardView>(app.core, Topics.agentCard(station, key))
        val a = chat.value?.agents?.firstOrNull { it.session.key == key } ?: agent
        val s = a.session
        // The account it runs on now, with what is left of it.
        val account = a.account?.let { it.name to it.quota } ?: a.profile?.let { it.name to it.quota }
        SheetGrab()
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ModelMark(s.maker, s.runtime, 40.dp, a.state, around = C.surface)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(s.agentText, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    AgentStatus(a)
                }
                if (a.working) StopButton(app, station, key)
            }
            AgentLines(card.value)
            AgentTiles(card.value)
            AgentNotes(card.value)
            Box(Modifier.height(12.dp))
            // Each row leaves the sheet for where it leads.
            InfoList {
                AgentRow(t("android-chat.agent.account"), account?.first?.let { if (s.profilePinned == true) it else t("android-chat.agent.account.auto", "name" to it) } ?: t("android-chat.agent.account.none"), { QuotaRings(account?.second) }) {
                    app.sheet = null; app.push(Screen.RunSettings(station, of, key))
                }
                AgentRow(t("android-chat.agent.history"), card.value?.work ?: t("android-chat.agent.history.none")) {
                    app.sheet = null; openHistory(app, station, of, key)
                }
                if (a.jobs.isNotEmpty()) AgentRow(t("android-chat.agent.jobs"), card.value?.jobs ?: t("android-chat.agent.jobs.idle")) { openJobs(app, station, of) }
            }
        }
    }
}

/** Stopping its turn, while it works: under way, a spinner in it, not pressed again. */
@Composable
private fun StopButton(app: AppState, station: String, key: String) {
    val busy = app.isDoing("session.stop", "station" to station, "key" to key)
    Row(
        Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(C.red.copy(alpha = 0.14f))
            .clickable(enabled = !busy) { app.act(t("android-chat.agent.stop"), done = t("android-chat.history.stopped")) { app.api(station).stop(key) } }
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (busy) Spinner(11.dp) else IconIn(Icons.Stop, 11.dp, C.red)
        Text(t("android-chat.agent.stop"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.red)
    }
}

/** A row of the card: what it is about, what there is of it, and where a tap leads. */
@Composable
private fun AgentRow(label: String, value: String, trailing: @Composable () -> Unit = {}, onClick: () -> Unit) {
    InfoRow(onClick = onClick) {
        Text(label, fontSize = 14.sp, color = C.muted)
        Text(value, fontSize = 14.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        trailing()
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/**
 * For how long an agent has stood where it does, in words: at work since its turn began, waiting as long as it has
 * (of at most), else when it was last at it; none when nothing says. Its clock runs each second.
 */
@Composable
internal fun agentSince(agent: ChatAgent): String? {
    val wait = agent.wait
    val since = agent.since
    if (wait == null && since == null) return agent.session.time?.get("lastActiveAt")?.ago
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    if (wait != null) {
        val most = wait.seconds?.let { " / ${elapsed(it * 1000)}" } ?: ""
        val waited = wait.seconds?.let { minOf(now, wait.since + it * 1000) } ?: now
        return elapsed(waited - wait.since) + most
    }
    return elapsed(now - since!!)
}

/** Where it stands, in words after a dot in its tone, and for how long; two lines at most (a need or a failure can be long). */
@Composable
internal fun AgentStatus(agent: ChatAgent, modifier: Modifier = Modifier) {
    val s = agent.session
    val since = agentSince(agent)
    val muted = C.muted
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        // On the first line's middle.
        Box(Modifier.padding(top = 6.dp).size(6.dp).clip(CircleShape).background(if (s.tone == "neutral") C.subtle else toneColor(s.tone)))
        Text(
            buildAnnotatedString {
                append(s.statusText)
                if (since != null) withStyle(SpanStyle(color = muted, fontFeatureSettings = "tnum")) { append(" · $since") }
            },
            fontSize = 13.sp, lineHeight = 18.sp, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Its latest lines (the core's): the things it did, then what it does now, in the ink. */
@Composable
private fun AgentLines(card: AgentCardView?) {
    val latest = card?.latest.orEmpty()
    if (latest.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        latest.forEach { l -> key(l.key) { Text(l.text, fontSize = 13.sp, lineHeight = 18.sp, color = if (l.now == true) C.ink else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) } }
    }
}

/** A figure of more letters than this is drawn a size down (three tiles share a phone's width). */
private const val LONG = 6

/**
 * The figures that say most, each large over its name, side by side: what it cost, the cache's hit rate, how full its
 * context is. In the ink, but a context worth a look in its level's colour.
 */
@Composable
internal fun AgentTiles(card: AgentCardView?, modifier: Modifier = Modifier.padding(top = 14.dp)) {
    val context = card?.context
    if (card?.cost == null && card?.cache == null && context == null) return
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        @Composable
        fun tile(figure: String, name: String, color: Color = C.ink) {
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(C.ink.copy(alpha = 0.05f)).padding(start = 12.dp, end = 12.dp, top = 9.dp, bottom = 8.dp)
                    .semantics(mergeDescendants = true) { contentDescription = "$name $figure" },
            ) {
                Box(Modifier.height(26.dp), contentAlignment = Alignment.CenterStart) {
                    Text(figure, fontSize = if (figure.length > LONG) 16.sp else 20.sp, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
                }
                Text(name, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        card?.cost?.let { tile(it, t("android-chat.agent.cost")) }
        card?.cache?.let { tile(it.text, t("android-chat.agent.cache")) }
        // How full, of a window that is known; else how much it holds.
        if (context != null) {
            if (context.unknown == true) tile(context.text, t("android-chat.agent.context"))
            else tile("${Math.round(context.percent)}%", t("android-chat.agent.context"), when (context.level) { "red" -> C.red; "amber" -> C.warn; else -> C.ink })
        }
    }
}

/** What is wrong (an account that cannot run, the disk filling up), a line each in its level's colour. */
@Composable
internal fun AgentNotes(card: AgentCardView?, modifier: Modifier = Modifier.padding(top = 10.dp)) {
    val notes = card?.attention.orEmpty()
    if (notes.isEmpty()) return
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        notes.forEach { a -> Text(a.text, fontSize = 13.sp, lineHeight = 18.sp, color = if (a.level == "amber") C.warn else C.red) }
    }
}
