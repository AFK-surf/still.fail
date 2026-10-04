// Files opened in the app and kept on this phone (the players, PDFs, a big file fetched a part at a time): in the app's
// cache, each under its own name (cache/files/<id>-<size>/<name>), so this page can say what they are. Nothing is
// deleted by itself: the page lists them with their sizes, and the person deletes one, or all.
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
import androidx.compose.foundation.layout.padding
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
import fail.still.android.LocalApp
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.t
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** A file kept on the phone: where it is, its name, how big, when last opened; `partial`, a fetch that stopped. */
class KeptFile(val file: File, val name: String, val size: Long, val opened: Long, val partial: Boolean)

object KeptFiles {
    fun dir(context: Context) = File(context.cacheDir, "files")

    /** Where a file (by its id and size) is kept, under its own name; its directory made. */
    fun place(context: Context, id: String, name: String, size: Long): File {
        val safe = name.substringAfterLast('/').replace(Regex("[\\u0000-\\u001f]"), "_").trimStart('.').take(120).ifEmpty { "file" }
        val home = File(dir(context), "${Integer.toHexString(id.hashCode())}-$size").apply { mkdirs() }
        return File(home, safe)
    }

    /** What is kept, the latest opened first: each file in its directory, and loose ones from before names were kept. */
    fun list(context: Context): List<KeptFile> {
        val out = ArrayList<KeptFile>()
        fun add(f: File) {
            val partial = f.name.endsWith(".part")
            out += KeptFile(f, if (partial) f.name.removeSuffix(".part") else f.name, f.length(), f.lastModified(), partial)
        }
        dir(context).listFiles()?.forEach { f -> if (f.isDirectory) f.listFiles()?.filter { it.isFile }?.forEach(::add) else add(f) }
        return out.sortedByDescending { it.opened }
    }

    /** Deletes a kept file (its directory with it, once empty). */
    fun delete(context: Context, kept: KeptFile) {
        kept.file.delete()
        kept.file.parentFile?.takeIf { it != dir(context) && it.list()?.isEmpty() == true }?.delete()
    }
}

@Composable
fun KeptFilesScreen() {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var version by remember { mutableIntStateOf(0) }
    var files by remember { mutableStateOf<List<KeptFile>?>(null) }
    LaunchedEffect(version) { files = withContext(Dispatchers.IO) { KeptFiles.list(context) } }
    val list = files
    val total = list?.sumOf { it.size } ?: 0L
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("android-settings.files.title"))
        PageNote(t("android-settings.files.note"))
        if (list != null && list.isEmpty()) PageNote(t("android-settings.files.none"))
        if (!list.isNullOrEmpty()) {
            SectionHeader(t("android-settings.files.total", "size" to fileSize(total), "n" to list.size), start = 24.dp)
            ListCard {
                list.forEach { f ->
                    ListRow {
                        Column(Modifier.weight(1f)) {
                            Text(f.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            val opened = since(f.opened)
                            Text(if (f.partial) t("android-settings.files.partial", "size" to fileSize(f.size)) else t("android-settings.files.meta", "size" to fileSize(f.size), "opened" to opened),
                                fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Box(Modifier.size(36.dp).clip(CircleShape).clickable {
                            scope.launch { withContext(Dispatchers.IO) { KeptFiles.delete(context, f) }; version++ }
                        }, contentAlignment = Alignment.Center) { IconIn(Icons.Trash, 18.dp, C.muted) }
                    }
                }
            }
            ListCard {
                ListRow(onClick = {
                    confirm(app, t("android-settings.files.clear.title"), t("android-settings.files.clear.text", "size" to fileSize(total)), t("android-settings.files.clear.action"), danger = true) {
                        withContext(Dispatchers.IO) { KeptFiles.list(context).forEach { KeptFiles.delete(context, it) } }
                        version++
                    }
                }) { Text(t("android-settings.files.clear.action"), fontSize = 15.sp, color = C.red) }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

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
