package fail.still.android.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.*
import fail.still.android.ui.*
import kotlinx.serialization.json.*

@Composable
fun AutomaticDecisionsScreen() {
    val app = LocalApp.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("web-pages.automaticDecisions.title"))
        ListCard {
            ListRow(onClick = { app.push(Screen.AutomaticDecisionCompletion) }) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(t("web-pages.automaticDecisions.completion"), color = C.ink, fontSize = 15.sp)
                    Text(t("web-pages.automaticDecisions.completionShort"), fontSize = 13.sp, color = C.muted)
                }
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
    }
}

@Composable
fun AutomaticDecisionCompletionScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("web-pages.automaticDecisions.title"), app::pop)
        LargeTitle("", t("web-pages.automaticDecisions.completion"))
        topic.value?.forEach { station -> key(station.station) {
            val view = station.overview?.automaticDecisions
            if (station.online && view != null) {
                AutomaticDecisionPanel(station.station, station.name, view)
            } else {
                SectionHeader(station.name, start = 24.dp)
                PageNote(t(when {
                    !station.online -> "web-pages.automaticDecisions.offlineNote"
                    station.overview == null -> "web-pages.automaticDecisions.connecting"
                    else -> "web-pages.automaticDecisions.upgrade"
                }))
            }
        } } ?: PageNote(topic.error?.message ?: t("web-pages.automaticDecisions.reading"))
        if (topic.value?.isEmpty() == true) PageNote(t("web-pages.automaticDecisions.addStation"))
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
private fun AutomaticDecisionPanel(station: String, name: String, view: AutomaticDecisionView) {
    val app = LocalApp.current
    if (!view.canEdit) { SectionHeader(name, start = 24.dp); PageNote(t("web-pages.automaticDecisions.adminOnly")); return }
    val form = remember(station) { java.util.UUID.randomUUID().toString() }
    val topic by rememberTopic<AutomaticDecisionDraft>(app.core, buildJsonObject { put("topic", "decisionForm"); put("station", station); put("form", form) })
    fun act(action: String, input: JsonObject = buildJsonObject {}) {
        app.act(t("web-pages.automaticDecisions.configAction"), if (action == "save") t("web-pages.automaticDecisions.saved") else null) {
            app.core.call("automaticDecisions.form.$action", buildJsonObject { put("station", station); put("form", form); put("input", input) })
        }
    }
    fun edit(key: String, value: JsonElement) = act("edit", buildJsonObject { put(key, value) })
    LaunchedEffect(station, form) { act("open") }
    DisposableEffect(station, form) { onDispose { act("drop") } }
    val d = topic.value
    if (d == null) { PageNote(topic.error?.message ?: t("web-pages.automaticDecisions.readingConfig")); return }
    val saving = app.isDoing("automaticDecisions.form.save", "station" to station, "form" to form)
    val refreshing = app.isDoing("automaticDecisions.refresh", "station" to station)
    val busy = d.pending || saving
    val model = view.models.find { it.id == d.model }
    Row(Modifier.fillMaxWidth().padding(end = 20.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { SectionHeader(name, start = 24.dp) }
        if (refreshing) Spinner(16.dp) else NavButton(Icons.Refresh, onClick = {
            app.act(t("web-pages.automaticDecisions.refreshAction"), t("web-pages.automaticDecisions.refreshed")) { app.core.call("automaticDecisions.refresh", buildJsonObject { put("station", station) }) }
        })
    }
    val refreshFailed = app.failedOf("automaticDecisions.refresh", "station" to station)
    refreshFailed?.let { PageNote(it) }
    ListCard {
        ListRow(onClick = if (busy) null else ({ edit("enabled", JsonPrimitive(!d.enabled)) })) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(t("web-pages.automaticDecisions.enabled"), color = C.ink, fontSize = 15.sp)
            }
            Switch(d.enabled)
        }
        GoRow(t("web-pages.automaticDecisions.model"), model?.name ?: if (d.model.isEmpty()) t("web-pages.automaticDecisions.pickModel") else t("web-pages.automaticDecisions.unavailable", "model" to d.model)) {
            if (!busy) app.sheet = SheetSpec(0.5f) {
                SheetGrab(); SheetHead(t("web-pages.automaticDecisions.model"))
                d.pick?.let { pick -> ModelList(pick.options, "codex", d.model) { model -> app.sheet = null; edit("model", JsonPrimitive(model)) } }
            }
        }
        // Asked of the station as saved: only once the rule is on there, and nothing unsaved.
        if (view.canReview == true && view.settings.completion?.enabled == true && !d.dirty) {
            val reviewing = app.isDoing("automaticDecisions.review", "station" to station)
            ListRow(onClick = if (busy || reviewing) null else ({
                app.act(t("web-pages.automaticDecisions.reviewAction"), t("web-pages.automaticDecisions.reviewStarted")) { app.core.call("automaticDecisions.review", buildJsonObject { put("station", station) }) }
            })) {
                Text(t("web-pages.automaticDecisions.review"), color = C.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
                DoingMark(reviewing, app.failedOf("automaticDecisions.review", "station" to station))
            }
        }
    }

    if (d.dirty) Row(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Button(t("web-pages.automaticDecisions.save"), primary = true, busy = saving, enabled = !busy) { act("save") }
        DoingMark(false, app.failedOf("automaticDecisions.form.save", "station" to station, "form" to form))
    }
    view.policy?.let { ArchivePolicySection(station, it) }
}

/** The station's archive policy (web mobile/AutomaticDecisions.tsx PolicySection): its words and its options in two groups,
 *  each with the chats the checks put there; edited in the core's draft (policyForm). */
@Composable
private fun ArchivePolicySection(station: String, policy: ArchivePolicyView) {
    val app = LocalApp.current
    val form = remember(station) { java.util.UUID.randomUUID().toString() }
    val topic by rememberTopic<ArchivePolicyDraft>(app.core, buildJsonObject { put("topic", "policyForm"); put("station", station); put("form", form) })
    fun call(action: String, input: JsonObject = buildJsonObject {}) = app.core.call("automaticDecisions.policy.$action", buildJsonObject { put("station", station); put("form", form); put("input", input) })
    fun edit(input: JsonObject) = app.act(t("web-pages.archivePolicy.editAction")) { call("edit", input) }
    LaunchedEffect(station, form) { app.act(t("web-pages.archivePolicy.readAction")) { call("open") } }
    DisposableEffect(station, form) { onDispose { app.act(t("web-pages.archivePolicy.closeAction")) { call("drop") } } }
    var editing by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf<String?>(null) }
    val d = topic.value
    fun group(archive: Boolean) = t(if (archive) "web-pages.archivePolicy.archive" else "web-pages.archivePolicy.keep")
    if (editing && d != null) {
        val saving = app.isDoing("automaticDecisions.policy.save", "station" to station, "form" to form)
        SectionHeader(t("web-pages.archivePolicy.title"), start = 24.dp)
        Box(Modifier.padding(horizontal = 20.dp)) { Field(d.policy, { edit(buildJsonObject { put("policy", it) }) }, t("web-pages.archivePolicy.title"), lines = 5) }
        listOf(true, false).forEach { archive ->
            SectionHeader(group(archive), start = 24.dp)
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                d.options.filter { it.archive == archive }.forEach { o -> key(o.key) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Field(o.name, { edit(buildJsonObject { put("option", o.key); put("name", it) }) }, t("web-pages.archivePolicy.name"))
                        Field(o.rubric, { edit(buildJsonObject { put("option", o.key); put("rubric", it) }) }, t("web-pages.archivePolicy.rubric"), lines = 2)
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            TextAction(t(if (o.archive) "web-pages.archivePolicy.toKeep" else "web-pages.archivePolicy.toArchive"), C.accent, !d.pending) { edit(buildJsonObject { put("option", o.key); put("archive", !o.archive) }) }
                            TextAction(t("web-pages.archivePolicy.remove"), C.red, !d.pending) { edit(buildJsonObject { put("remove", o.key) }) }
                        }
                    }
                } }
                TextAction(t("web-pages.archivePolicy.add"), C.accent, !d.pending) { edit(buildJsonObject { put("add", archive) }) }
            }
        }
        app.failedOf("automaticDecisions.policy.save", "station" to station, "form" to form)?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp)) }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("web-pages.archivePolicy.cancel"), primary = false, enabled = !d.pending) { edit(buildJsonObject { put("reset", true) }); editing = false }
            Button(t("web-pages.archivePolicy.save"), primary = true, busy = saving, enabled = d.dirty && !d.pending) {
                app.act(t("web-pages.archivePolicy.saveAction"), t("web-pages.archivePolicy.saved")) { call("save"); editing = false }
            }
        }
        return
    }
    Row(Modifier.fillMaxWidth().padding(end = 20.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { SectionHeader(t("web-pages.archivePolicy.title"), start = 24.dp) }
        if (d != null) NavButton(Icons.Edit, onClick = { editing = true })
    }
    Text(policy.text, fontSize = 14.sp, color = C.ink, lineHeight = 22.sp, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 10.dp))
    listOf(true, false).forEach { archive ->
        SectionHeader(group(archive), start = 24.dp)
        ListCard {
            policy.options.filter { it.archive == archive }.forEach { o -> key(o.id) {
                ListRow(onClick = if (o.count > 0) ({ open = if (open == o.id) null else o.id }) else null) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(o.name, color = C.ink, fontSize = 15.sp)
                        Text(o.rubric, fontSize = 13.sp, color = C.muted)
                    }
                    Text("${o.count}", fontSize = 13.sp, color = C.muted)
                }
                if (open == o.id) o.chats.forEach { c ->
                    ListRow(onClick = { app.push(Screen.Chat(station, ChatOf.Session(c.session))) }) {
                        Text(c.title, fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = 12.dp))
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
            } }
        }
    }
    val line = listOfNotNull(policy.changeText, policy.summaryText.ifEmpty { null }).joinToString(" · ")
    Text(line, fontSize = 13.sp, color = if (policy.failed > 0) C.red else C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 10.dp))
}

/** A word that does something (no frame), as the web's LinkButton. */
@Composable
private fun TextAction(label: String, color: androidx.compose.ui.graphics.Color, enabled: Boolean, onClick: () -> Unit) =
    Text(label, fontSize = 14.sp, color = if (enabled) color else C.subtle, modifier = Modifier.clickable(enabled = enabled, onClick = onClick).padding(vertical = 4.dp))
