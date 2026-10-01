// An agent's words with its files (web/src/Chat.tsx → ProseWithFiles, PlacedFile, FileLink): those its text names
// are drawn where it names them (an HTML one as its visualization, an image whole, several images of one paragraph
// side by side), the rest below it, as they always were.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import fail.still.android.data.Attachment
import fail.still.android.ui.LocalFollowUp
import fail.still.android.ui.Markdown
import fail.still.android.ui.Placing
import fail.still.android.ui.VizFile
import fail.still.android.ui.VizOpen
import fail.still.android.ui.placeFiles

private val IMAGE = Regex("\\.(png|jpe?g|gif|webp)$", RegexOption.IGNORE_CASE)
private val HTML = Regex("\\.html?$", RegexOption.IGNORE_CASE)

/**
 * An agent's Markdown with its files: those its text names shown there, the rest below it. `draft`: where words a
 * visualization asks to send go (the composer), for the person to send.
 */
@Composable
internal fun AgentWords(ctx: Here, text: String, files: List<Attachment>, draft: Draft? = null) {
    val (placed, rest) = remember(text, files) { placeFiles(text, files) }
    var opened by remember { mutableStateOf<Attachment?>(null) }
    val placing = if (placed.isEmpty()) null else Placing(
        files = placed,
        shown = { f -> PlacedFile(ctx, f) },
        row = { f, size ->
            val owner = ctx.owner(f)
            if (owner != null && IMAGE.containsMatchIn(f.name)) StationImage(ctx.station, owner, f, size)
            // Markdown's ![] can place a video (or any file), too. Its card must open the same preview as a link.
            else FileCard(f.name, f.size, onClick = if (owner != null) ({ opened = f }) else null)
        },
        open = { opened = it },
    )
    val followUp: ((String) -> Boolean)? = draft?.let { d -> { words -> d.text = if (d.text.isBlank()) words else "${d.text.trimEnd()}\n$words"; d.focus++; true } }
    Column {
        CompositionLocalProvider(LocalFollowUp provides followUp) { Markdown(text, placing = placing) }
        if (rest.isNotEmpty()) Box(Modifier.padding(top = 4.dp)) { Files(ctx, rest) }
    }
    opened?.let { f -> OpenedFile(ctx, f) { opened = null } }
}

/**
 * A file the text places on a line of its own: an HTML one is a visualization, drawn there (how agents make one is
 * the stillfail-viz skill); any other shows as below the text.
 */
@Composable
private fun PlacedFile(ctx: Here, file: Attachment) {
    val owner = ctx.owner(file)
    if (owner != null && HTML.containsMatchIn(file.name)) VizFile(ctx.station, owner, file) { FileCard(file.name, file.size) }
    else Files(ctx, listOf(file))
}

/** A file a link within a sentence names, opened: a visualization over the whole screen; any other as its message shows it, over the page. */
@Composable
private fun OpenedFile(ctx: Here, file: Attachment, onClose: () -> Unit) {
    val owner = ctx.owner(file)
    if (owner != null && HTML.containsMatchIn(file.name)) return VizOpen(ctx.station, owner, file, onClose)
    // Any other opens in the file preview (FilePreview.kt), as a tap on it below the text does.
    if (owner != null) return FilePreview(ctx.station, owner, file, { ctx.images() }, onClose)
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClose),
            contentAlignment = Alignment.Center,
        ) { Files(ctx, listOf(file)) }
    }
}
