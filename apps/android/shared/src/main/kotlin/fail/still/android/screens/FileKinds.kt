// What a file is by its name (web/src/FilePreview.tsx kindOf), a file of a chat or a drive as the viewer knows it, and
// saving one to the phone's Downloads: the chat's and the drive's both (2026-10-18).
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.data.DriveCache
import fail.still.android.data.t
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.provider.MediaStore
import android.util.LruCache
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ThumbHash
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import fail.still.android.ui.fileSize
import fail.still.android.ui.chatInk

enum class PreviewKind { Image, Video, Audio, Pdf, Markdown, Csv, Html, Code, Text;
    val label: String get() = t("android-chat.kind." + name.lowercase())
}

/** What a file shows as, by its name; `kind` null: look at its bytes to know. */
class Kind(val kind: PreviewKind?, val type: String, val language: String? = null)

private val MEDIA = mapOf(
    "png" to (PreviewKind.Image to "image/png"), "jpg" to (PreviewKind.Image to "image/jpeg"), "jpeg" to (PreviewKind.Image to "image/jpeg"),
    "gif" to (PreviewKind.Image to "image/gif"), "webp" to (PreviewKind.Image to "image/webp"), "svg" to (PreviewKind.Image to "image/svg+xml"),
    "avif" to (PreviewKind.Image to "image/avif"), "bmp" to (PreviewKind.Image to "image/bmp"), "ico" to (PreviewKind.Image to "image/x-icon"),
    "mp4" to (PreviewKind.Video to "video/mp4"), "m4v" to (PreviewKind.Video to "video/mp4"), "webm" to (PreviewKind.Video to "video/webm"),
    "mov" to (PreviewKind.Video to "video/quicktime"), "ogv" to (PreviewKind.Video to "video/ogg"),
    "mp3" to (PreviewKind.Audio to "audio/mpeg"), "m4a" to (PreviewKind.Audio to "audio/mp4"), "aac" to (PreviewKind.Audio to "audio/aac"),
    "wav" to (PreviewKind.Audio to "audio/wav"), "ogg" to (PreviewKind.Audio to "audio/ogg"), "oga" to (PreviewKind.Audio to "audio/ogg"),
    "opus" to (PreviewKind.Audio to "audio/ogg"), "flac" to (PreviewKind.Audio to "audio/flac"),
    "pdf" to (PreviewKind.Pdf to "application/pdf"),
    "md" to (PreviewKind.Markdown to "text/markdown"), "markdown" to (PreviewKind.Markdown to "text/markdown"),
    "csv" to (PreviewKind.Csv to "text/csv"), "tsv" to (PreviewKind.Csv to "text/tab-separated-values"),
    "html" to (PreviewKind.Html to "text/html"), "htm" to (PreviewKind.Html to "text/html"),
)

/** Extensions known by another name; the rest are tried as they are. */
private val LANGUAGE = mapOf(
    "mjs" to "js", "cjs" to "js", "mts" to "ts", "cts" to "ts", "h" to "c", "hh" to "cpp", "hpp" to "cpp", "cc" to "cpp", "cxx" to "cpp",
    "kts" to "kotlin", "yml" to "yaml", "zsh" to "bash", "sh" to "bash", "patch" to "diff", "htm" to "html", "conf" to "ini", "cfg" to "ini",
    "env" to "dotenv", "gradle" to "groovy", "plist" to "xml", "svg" to "xml",
)

private val PLAIN = setOf("txt", "text", "log", "out", "err", "lock")

private val NAMED = mapOf("dockerfile" to "docker", "makefile" to "make", "cmakelists.txt" to "cmake")

private val CODE = setOf(
    "ts", "tsx", "js", "jsx", "json", "jsonc", "json5", "py", "rs", "go", "java", "kt", "swift", "c", "cpp", "cs", "rb", "php", "bash", "fish", "ps1",
    "yaml", "toml", "xml", "sql", "css", "scss", "less", "html", "vue", "svelte", "lua", "dart", "diff", "ini", "dotenv", "groovy", "scala", "r", "pl", "ex", "exs",
    "erl", "hs", "ml", "clj", "zig", "nim", "proto", "graphql", "tex", "vim", "nix", "tf", "hcl", "docker", "make", "cmake", "asm", "wasm", "sol", "prisma", "astro",
)

fun kindOf(name: String): Kind {
    val lower = name.lowercase()
    NAMED[lower]?.let { return Kind(PreviewKind.Code, "text/plain", it) }
    val dot = lower.lastIndexOf('.')
    val ext = if (dot > 0) lower.substring(dot + 1) else ""
    MEDIA[ext]?.let { (kind, type) -> return Kind(kind, type, if (kind == PreviewKind.Html) "html" else null) }
    if (ext in PLAIN) return Kind(PreviewKind.Text, "text/plain")
    val language = LANGUAGE[ext] ?: ext
    if (language in CODE) return Kind(PreviewKind.Code, "text/plain", language)
    return Kind(null, "application/octet-stream")
}

fun isImage(name: String) = kindOf(name).kind == PreviewKind.Image

/**
 * A file of a station's drive shown by the viewer (drive/DriveScreen.kt), as the viewer knows files by a session's key:
 * the key names its root and when it last changed instead (a file changed is fetched anew, not taken from what is kept).
 */
object DriveKey {
    private const val TAG = "drive\u0001"
    fun of(root: String, mtime: Long) = "$TAG$mtime\u0001$root"
    /** When the file a key names last changed; null for a session's key. */
    fun mtimeOf(key: String): Long? = if (key.startsWith(TAG)) key.removePrefix(TAG).substringBefore('\u0001').toLongOrNull() else null
    /** The root a key names; null for a session's key. */
    fun rootOf(key: String): String? = if (key.startsWith(TAG)) key.removePrefix(TAG).substringAfter('\u0001') else null
}

/** A file and the session that keeps it. */
class Shown(val key: String, val file: Attachment)

/** Puts a file in the phone's Downloads. */
suspend fun download(context: Context, name: String, bytes: ByteArray, type: String? = null): Boolean = withContext(Dispatchers.IO) {
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        (type ?: kindOf(name).type).takeIf { it != "application/octet-stream" }?.let { put(MediaStore.Downloads.MIME_TYPE, it) }
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
}

/** A file on the phone's disk saved to Downloads (a big one, not read into memory). */
suspend fun download(context: Context, name: String, from: File): Boolean = withContext(Dispatchers.IO) {
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        kindOf(name).type.takeIf { it != "application/octet-stream" }?.let { put(MediaStore.Downloads.MIME_TYPE, it) }
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
    context.contentResolver.openOutputStream(uri)?.use { out -> from.inputStream().use { it.copyTo(out, 1 shl 16) } } != null
}
