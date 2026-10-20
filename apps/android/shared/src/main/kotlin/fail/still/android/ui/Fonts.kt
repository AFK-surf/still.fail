// The faces the app is set in (docs/fonts.md): three places, each as chosen on this device (the core's prefs `faces`,
// client/core-ts/src/fonts.ts): ui, the app's own words (MaterialTheme's type, which every Text without a face of
// its own takes); text, what people and agents wrote (Markdown, the composer); code (CodeFont). A face still.fail keeps
// is fetched when chosen, kept in files/fonts by the hash of what it is, and used once all its files are here; until
// then the app's own face stands in.
package fail.still.android.ui

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import fail.still.android.data.FontFace
import fail.still.android.data.FontsView
import fail.still.android.data.t
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/** Each place's face: null, the app's own (the system's for ui and text). */
@Immutable
data class AppFonts(val ui: FontFamily? = null, val text: FontFamily? = null, val code: FontFamily = JetBrainsMono)

val LocalFonts = staticCompositionLocalOf { AppFonts() }

/** The code face as chosen; JetBrains Mono, the app's own. */
val CodeFont: FontFamily @Composable @ReadOnlyComposable get() = LocalFonts.current.code

/** What people and agents wrote: its face as chosen, else ui's (null: the system's). */
val TextFont: FontFamily? @Composable @ReadOnlyComposable get() = LocalFonts.current.text

/** The app's own words, where a style is made whole rather than taken from the theme (null: the system's). */
val UiFont: FontFamily? @Composable @ReadOnlyComposable get() = LocalFonts.current.ui

val Mono: TextStyle @Composable @ReadOnlyComposable get() = TextStyle(fontFamily = CodeFont, fontSize = 12.sp, lineHeight = 18.sp)

/** The faces' files: fetched, kept, made into families; what is being fetched and what failed, by face. */
object FaceFiles {
    private var dir: File? = null
    /** A face being fetched: how far, 0 to 1. */
    val fetching = mutableStateMapOf<String, Float>()
    /** A face whose fetch failed: why. */
    val failed = mutableStateMapOf<String, String>()
    /** Families made, by their files' hashes. */
    private val made = HashMap<String, FontFamily>()
    /** Counts the fetches finished: what reads it is made again when a face's files are all here. */
    var fetched by mutableIntStateOf(0)
        private set

    fun init(context: Context) {
        if (dir == null) dir = File(context.filesDir, "fonts").apply { mkdirs() }
    }

    private fun key(face: FontFace) = face.files.orEmpty().joinToString(",") { it.sha256 }
    private fun fileOf(sha: String) = dir?.let { File(it, "$sha.ttf") }

    /** Its family, once all its files are here; null before, and for one with none (the app's own). */
    fun family(face: FontFace): FontFamily? {
        val files = face.files.orEmpty()
        if (files.isEmpty()) return null
        made[key(face)]?.let { return it }
        if (files.any { fileOf(it.sha256)?.exists() != true }) return null
        return familyOf(face).also { made[key(face)] = it }
    }

    @OptIn(ExperimentalTextApi::class)
    private fun familyOf(face: FontFace): FontFamily = FontFamily(face.files.orEmpty().flatMap { f ->
        val file = fileOf(f.sha256)!!
        if (f.weight == 0L) listOf(FontWeight.Light, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold).map {
            Font(file, it, variationSettings = FontVariation.Settings(FontVariation.weight(it.weight)))
        } else listOf(Font(file, FontWeight(f.weight.toInt())))
    })

    /** Fetches what of it is not here yet (each file whole, its hash checked), saying how far as it goes. */
    suspend fun fetch(face: FontFace) {
        if (face.files.isNullOrEmpty() || face.id in fetching || family(face) != null) return
        fetching[face.id] = 0f
        failed.remove(face.id)
        try {
            withContext(Dispatchers.IO) {
                var done = 0L
                for (f in face.files.orEmpty()) {
                    val target = fileOf(f.sha256) ?: error("no place for fonts")
                    if (target.exists()) { done += f.bytes; continue }
                    val part = File(target.path + ".part")
                    val digest = MessageDigest.getInstance("SHA-256")
                    val connection = URL(f.url).openConnection() as HttpURLConnection
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 30_000
                    try {
                        if (connection.responseCode != 200) throw IOException(t("android-misc.updates.httpStatus", "status" to connection.responseCode))
                        val counted = object : java.io.FilterInputStream(connection.inputStream) {
                            override fun read(b: ByteArray, off: Int, len: Int): Int = super.read(b, off, len).also { n ->
                                if (n <= 0) return@also
                                done += n
                                // Said each percent, not each read.
                                val p = if (face.bytes > 0) (done * 100 / face.bytes).coerceAtMost(100) / 100f else 0f
                                if (p != fetching[face.id]) fetching[face.id] = p
                            }
                        }
                        GZIPInputStream(counted, 64 * 1024).use { input ->
                            part.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    digest.update(buffer, 0, read)
                                    output.write(buffer, 0, read)
                                }
                            }
                        }
                    } finally {
                        connection.disconnect()
                    }
                    val got = digest.digest().joinToString("") { "%02x".format(it) }
                    if (got != f.sha256) { part.delete(); throw IOException(t("android-settings.fonts.damaged")) }
                    if (!part.renameTo(target)) throw IOException(t("android-settings.fonts.damaged"))
                }
            }
            fetched++
        } catch (e: Exception) {
            failed[face.id] = e.message ?: e.toString()
        } finally {
            fetching.remove(face.id)
        }
    }

    /** Faces' previews made, by face (the fonts page's characters alone: each face shown in itself before it is fetched). */
    val previews = mutableStateMapOf<String, FontFamily>()

    private fun previewFile(face: FontFace): File? = face.preview?.let { url -> dir?.let { File(it, "${face.id}-${url.substringAfterLast('/')}") } }

    @OptIn(ExperimentalTextApi::class)
    private fun previewOf(file: File, variable: Boolean): FontFamily =
        if (variable) FontFamily(listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold).map { Font(file, it, variationSettings = FontVariation.Settings(FontVariation.weight(it.weight))) })
        else FontFamily(Font(file, FontWeight.Normal))

    /** Its preview, fetched if it is not here (a few tens of KB); kept whatever is chosen. */
    suspend fun fetchPreview(face: FontFace) {
        if (face.id in previews) return
        val file = previewFile(face) ?: return
        val variable = face.files.orEmpty().any { it.weight == 0L }
        try {
            withContext(Dispatchers.IO) {
                if (!file.exists()) {
                    val connection = URL(face.preview).openConnection() as HttpURLConnection
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 30_000
                    try {
                        if (connection.responseCode != 200) return@withContext
                        val part = File(file.path + ".part")
                        connection.inputStream.use { input -> part.outputStream().use { input.copyTo(it) } }
                        part.renameTo(file)
                    } finally {
                        connection.disconnect()
                    }
                }
            }
            if (file.exists()) previews[face.id] = previewOf(file, variable)
        } catch (_: Exception) {
            // Not shown in itself: its name in the app's face.
        }
    }

    /** Only the files of `keep` stay: another face's go once it is not chosen (the previews stay, being small). */
    fun prune(keep: List<FontFace>) {
        val wanted = keep.flatMap { it.files.orEmpty() }.map { "${it.sha256}.ttf" }.toSet()
        dir?.listFiles()?.forEach { if (it.name !in wanted && !it.name.endsWith(".part") && !it.name.contains("-preview-")) it.delete() }
        made.keys.retainAll(keep.map { key(it) }.toSet())
    }
}

/**
 * The faces as chosen (`faces`, null from a core before them), each fetched if it is not here: a face being fetched is
 * the app's own until its files are all here.
 */
@Composable
fun rememberFonts(faces: FontsView?): AppFonts {
    val chosen = listOfNotNull(faces?.ui, faces?.text, faces?.code)
    for (face in chosen.distinctBy { it.id }) LaunchedEffect(face.id, face.files) { FaceFiles.fetch(face) }
    // Read, so a face fetched makes this again.
    FaceFiles.fetched
    val ui = faces?.ui?.let { FaceFiles.family(it) }
    val text = faces?.text?.let { FaceFiles.family(it) } ?: ui
    val code = faces?.code?.let { FaceFiles.family(it) } ?: JetBrainsMono
    LaunchedEffect(chosen.map { it.id }, FaceFiles.fetching.size) { if (FaceFiles.fetching.isEmpty() && faces != null) FaceFiles.prune(chosen) }
    return remember(ui, text, code) { AppFonts(ui, text, code) }
}
