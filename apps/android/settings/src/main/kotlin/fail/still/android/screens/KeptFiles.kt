// What this phone keeps, by chat: each chat's messages as the core keeps them (`cache.usage`) and the files opened in it
// (the players, PDFs, a big file fetched a part at a time: in the app's cache, each under its own name in a directory
// of its own, cache/files/<id>-<size>/<name>, with the station and session it came from beside it); then what belongs
// to no chat: files opened from stations' drives (DriveCache, which lets the least lately opened go by itself past its
// bounds), web pages' cache, update packages, other temporary files, and the core's own data. Nothing else is deleted by
// itself: a file, a chat's all, or everything, when the person says.
package fail.still.android.screens

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.data.t
import fail.still.android.data.DriveCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import java.io.File
import fail.still.android.ui.fileSize

/** How long ago, in the app's words: just now, minutes, hours, days. */
private fun since(at: Long): String {
    val minutes = (System.currentTimeMillis() - at) / 60_000
    return when {
        minutes < 1 -> t("android-settings.files.justNow")
        minutes < 60 -> t("android-settings.files.minutes", "n" to minutes)
        minutes < 24 * 60 -> t("android-settings.files.hours", "n" to minutes / 60)
        else -> t("android-settings.files.days", "n" to minutes / (24 * 60))
    }
}

/** What is kept, read now, and again whenever `version` changes. */
@Composable
private fun rememberKept(version: Int): Kept? {
    val app = LocalApp.current
    val context = LocalContext.current
    var kept by remember { mutableStateOf<Kept?>(null) }
    LaunchedEffect(version) { kept = KeptFiles.read(app, context) }
    return kept
}

@Composable
private fun SizeRow(title: String, sub: String?, size: Long, onClick: (() -> Unit)?, chevron: Boolean = onClick != null) {
    ListRow(onClick = onClick) {
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(fileSize(size), fontSize = 14.sp, color = C.muted)
        if (chevron) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

@Composable
private fun DangerRow(label: String, onClick: () -> Unit) {
    ListCard { ListRow(onClick = onClick) { Text(label, fontSize = 15.sp, color = C.red) } }
}

/** Everything this phone keeps: by chat, then what belongs to no chat. */
@Composable
fun KeptFilesScreen() {
    val app = LocalApp.current
    val context = LocalContext.current
    var version by remember { mutableIntStateOf(0) }
    val kept = rememberKept(version)
    fun ask(title: String, text: String, run: suspend () -> Unit) =
        confirm(app, title, text, t("android-settings.files.clear.action"), danger = true) { run(); version++ }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("android-settings.files.title"))
        PageNote(t("android-settings.files.note"))
        if (kept != null) {
            SectionHeader(t("android-settings.files.byChat"), t("android-settings.files.total", "size" to fileSize(kept.total)), start = 24.dp)
            if (kept.chats.isEmpty()) PageNote(t("android-settings.files.none"))
            else ListCard {
                kept.chats.forEach { c ->
                    val sub = if (c.files.isEmpty()) t("android-settings.files.chat.messages", "size" to fileSize(c.messages))
                    else t("android-settings.files.chat.both", "size" to fileSize(c.messages), "n" to c.files.size, "files" to fileSize(c.files.sumOf { it.size }))
                    SizeRow(c.title, sub, c.size, { app.push(Screen.KeptChat(c.station, c.thread)) })
                }
            }
            SectionHeader(t("android-settings.files.other"), start = 24.dp)
            ListCard {
                if (kept.loose.isNotEmpty()) SizeRow(t("android-settings.files.loose"), t("android-settings.files.count", "n" to kept.loose.size), kept.loose.sumOf { it.size }, { app.push(Screen.KeptChat(null, null)) })
                SizeRow(t("android-settings.files.drive"), t("android-settings.files.drive.sub"), kept.drive, if (kept.drive > 0) ({ ask(t("android-settings.files.drive"), t("android-settings.files.drive.text")) { KeptFiles.clearDrive(context) } }) else null, chevron = false)
                SizeRow(t("android-settings.files.web"), null, kept.web, if (kept.web > 0) ({ ask(t("android-settings.files.web"), t("android-settings.files.web.text")) { KeptFiles.clearWeb(context) } }) else null, chevron = false)
                SizeRow(t("android-settings.files.updates"), null, kept.updates, if (kept.updates > 0) ({ ask(t("android-settings.files.updates"), t("android-settings.files.updates.text")) { KeptFiles.clearUpdates(context) } }) else null, chevron = false)
                SizeRow(t("android-settings.files.temporary"), null, kept.temporary, if (kept.temporary > 0) ({ ask(t("android-settings.files.temporary"), t("android-settings.files.temporary.text")) { KeptFiles.clearTemporary(context) } }) else null, chevron = false)
                SizeRow(t("android-settings.files.data"), t("android-settings.files.data.text"), kept.data, null)
            }
            if (kept.total > kept.data) DangerRow(t("android-settings.files.clearAll")) {
                ask(t("android-settings.files.clearAll.title"), t("android-settings.files.clearAll.text", "size" to fileSize(kept.total - kept.data))) { KeptFiles.clearAll(app, context, kept) }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** A chat's: its messages and the files opened in it, each to delete, or all of it. No chat: files of no chat known. */
@Composable
fun KeptChatScreen(station: String?, thread: Long?) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var version by remember { mutableIntStateOf(0) }
    val kept = rememberKept(version)
    val chat = kept?.chats?.firstOrNull { it.station == station && it.thread == thread }
    val files = if (station == null) kept?.loose.orEmpty() else chat?.files.orEmpty()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.files.title"), app::pop)
        LargeTitle("", if (station == null) t("android-settings.files.loose") else chat?.title ?: "")
        if (kept != null) {
            if (chat != null) ListCard {
                SizeRow(t("android-settings.files.messages"), t("android-settings.files.messages.text"), chat.messages, if (chat.messages > 0) ({
                    confirm(app, t("android-settings.files.messages"), t("android-settings.files.messages.clear"), t("android-settings.files.clear.action"), danger = true) {
                        app.core.call("cache.clear", buildJsonObject { put("station", chat.station); put("thread", chat.thread) }); version++
                    }
                }) else null, chevron = false)
            }
            if (files.isNotEmpty()) {
                SectionHeader(t("android-settings.files.files"), t("android-settings.files.filesTotal", "n" to files.size, "size" to fileSize(files.sumOf { it.size })), start = 24.dp)
                ListCard {
                    files.forEach { f ->
                        ListRow {
                            Column(Modifier.weight(1f)) {
                                Text(f.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(if (f.partial) t("android-settings.files.partial", "size" to fileSize(f.size)) else t("android-settings.files.meta", "size" to fileSize(f.size), "opened" to since(f.opened)),
                                    fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Box(Modifier.size(36.dp).clip(CircleShape).clickable {
                                scope.launch { withContext(Dispatchers.IO) { KeptFiles.delete(context, f) }; version++ }
                            }, contentAlignment = Alignment.Center) { IconIn(Icons.Trash, 18.dp, C.muted) }
                        }
                    }
                }
            }
            val all = (chat?.size ?: 0L) + if (station == null) files.sumOf { it.size } else 0L
            if (all > 0) DangerRow(t("android-settings.files.clearChat")) {
                confirm(app, t("android-settings.files.clearChat"), t("android-settings.files.clearChat.text", "size" to fileSize(all)), t("android-settings.files.clear.action"), danger = true) {
                    if (chat != null) KeptFiles.clearChat(app, context, chat) else withContext(Dispatchers.IO) { files.forEach { KeptFiles.delete(context, it) } }
                    version++
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}
