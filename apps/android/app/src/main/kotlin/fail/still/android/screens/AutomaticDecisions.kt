package fail.still.android.screens

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
fun AutomaticDecisionsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("web-pages.automaticDecisions.title"))
        topic.value?.forEach { station -> key(station.station) {
            val view = station.overview?.automaticDecisions
            when {
                !station.online -> PageNote(t("web-pages.automaticDecisions.offlineNote"))
                station.overview == null -> PageNote(t("web-pages.automaticDecisions.connecting"))
                view == null -> PageNote(t("web-pages.automaticDecisions.upgrade"))
                !view.canEdit -> PageNote(t("web-pages.automaticDecisions.adminOnly"))
                else -> AutomaticDecisionPanel(station.station, station.name, view)
            }
        } } ?: PageNote(topic.error?.message ?: t("web-pages.automaticDecisions.reading"))
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
private fun AutomaticDecisionPanel(station: String, name: String, view: AutomaticDecisionView) {
    val app = LocalApp.current
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
                Text(t("web-pages.automaticDecisions.completion"), color = C.ink, fontSize = 15.sp)
                Text(t("web-pages.automaticDecisions.completionShort"), fontSize = 13.sp, color = C.muted)
            }
            Switch(d.enabled)
        }
        GoRow(t("web-pages.automaticDecisions.model"), model?.name ?: if (d.model.isEmpty()) t("web-pages.automaticDecisions.pickModel") else t("web-pages.automaticDecisions.unavailable", "model" to d.model)) {
            if (!busy) app.sheet = SheetSpec(0.5f) {
                SheetGrab(); SheetHead(t("web-pages.automaticDecisions.model"))
                d.pick?.let { pick -> ModelList(pick.options, "codex", d.model) { model -> app.sheet = null; edit("model", JsonPrimitive(model)) } }
            }
        }
    }

    if (d.dirty) Row(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Button(t("web-pages.automaticDecisions.save"), primary = true, busy = saving, enabled = !busy) { act("save") }
        DoingMark(false, app.failedOf("automaticDecisions.form.save", "station" to station, "form" to form))
    }
    SectionHeader(t("web-pages.automaticDecisions.recent"), start = 24.dp)
    ListCard {
        if (view.recent.isEmpty()) ListRow { Text(t("web-pages.automaticDecisions.noRecords"), fontSize = 13.sp, color = C.muted) }
        view.recent.forEach { row -> ListRow(onClick = { app.push(Screen.Chat(station, ChatOf.Session(row.session))) }) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(row.title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    row.stamp?.let { Text(it.ago, fontSize = 12.sp, color = C.subtle) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(row.label, fontSize = 13.sp, color = if (row.accepted) C.muted else C.red)
                    Text("· ${row.model}", fontSize = 13.sp, color = C.muted)
                }
                row.error?.let { Text(it, fontSize = 12.sp, color = C.red) }
            }
        } }
    }
}
