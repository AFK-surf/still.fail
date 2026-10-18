// Pictures in a driven screen's clipboard, on the phone (docs/remote-screens.md "Clipboard and files"). A copy made on
// the screen is kept in the cache for the phone's clipboard to point at (a content:// URI of the app's FileProvider,
// image/png; the newest few kept, the rest deleted). A paste sends what the phone's clipboard holds: its picture as a
// PNG (another kind converted) where the screen carries pictures (the state's `clipboard` has `png`), else its text;
// past the protocol's bounds it is said, not sent. Only the core's `clipboard` types say what goes: from a station or a
// helper that does not name `png`, pictures are neither put on the phone nor sent.
package fail.still.android.remote

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

/** The most a clipboard carries each way (client/core-ts/src/screen-frames.ts): text's UTF-8 bytes, a picture's. */
const val CLIP_TEXT_MAX = 1024 * 1024
const val CLIP_PNG_MAX = 8 * 1024 * 1024

/** The most of a picture of another kind read to convert it (a photo's JPEG), and the most pixels decoded of one. */
const val CLIP_SOURCE_MAX = 32 * 1024 * 1024
const val CLIP_PIXELS_MAX = 16L * 1024 * 1024

/** A copy made on the screen, as the viewer puts it on the phone's clipboard. */
sealed interface Copied {
    class Text(val text: String) : Copied
    class Png(val bytes: ByteArray) : Copied
}

private val PNG_SIGNATURE = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)

/** `bytes` start as a PNG does. */
fun isPng(bytes: ByteArray): Boolean = bytes.size >= PNG_SIGNATURE.size && PNG_SIGNATURE.indices.all { bytes[it] == PNG_SIGNATURE[it] }

/** A copy of a picture the phone takes: a PNG, within its bound, from a screen that says it carries pictures. */
fun takesCopied(types: List<String>, bytes: ByteArray): Boolean = "png" in types && bytes.size in 1..CLIP_PNG_MAX && isPng(bytes)

/** What a paste takes of the phone's clipboard, the screen carrying `types`. */
enum class PasteKind { IMAGE, TEXT, NO_IMAGES, NO_TEXT, EMPTY }

/**
 * Its picture where the screen carries pictures, else its text where it carries text (as the web's paste does); what it
 * holds of a kind the screen does not carry is refused, said as such.
 */
fun pasteKind(types: List<String>, image: Boolean, text: Boolean): PasteKind = when {
    image && "png" in types -> PasteKind.IMAGE
    text && "text" in types -> PasteKind.TEXT
    image && !text -> PasteKind.NO_IMAGES
    text -> PasteKind.NO_TEXT
    else -> PasteKind.EMPTY
}

/** A picture's type, as a clip or its provider says it: an image (`image/…`). */
fun isImageType(type: String?): Boolean = type != null && type.trim().lowercase().startsWith("image/")

/** A picture readied to paste: its PNG, or why not. */
sealed interface Readied {
    class Png(val bytes: ByteArray) : Readied
    /** Past the bounds (8 MB as a PNG; to read or decode, for another kind). */
    data object TooLarge : Readied
    /** Not to be read, or no picture. */
    data object Unreadable : Readied
}

/** All of `input` while it is at most `max` bytes; null once it is more. */
fun readAtMost(input: InputStream, max: Int): ByteArray? {
    val out = ByteArrayOutputStream()
    val buffer = ByteArray(64 * 1024)
    while (true) {
        val got = input.read(buffer)
        if (got < 0) return out.toByteArray()
        if (out.size() + got > max) return null
        out.write(buffer, 0, got)
    }
}

/** A picture's bytes as the screen takes them: a PNG as it is, another kind as `convert` makes it one; within the bound. */
fun asPng(bytes: ByteArray, convert: (ByteArray) -> Readied): Readied {
    if (bytes.isEmpty()) return Readied.Unreadable
    if (isPng(bytes)) return if (bytes.size <= CLIP_PNG_MAX) Readied.Png(bytes) else Readied.TooLarge
    val made = convert(bytes)
    return if (made is Readied.Png && made.bytes.size > CLIP_PNG_MAX) Readied.TooLarge else made
}

/** A picture of another kind (JPEG, WebP, HEIF, GIF's first frame…) encoded as PNG; too many pixels are not decoded. */
fun encodePng(bytes: ByteArray): Readied {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return Readied.Unreadable
    if (bounds.outWidth.toLong() * bounds.outHeight > CLIP_PIXELS_MAX) return Readied.TooLarge
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return Readied.Unreadable
    return try {
        val out = ByteArrayOutputStream()
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) Readied.Unreadable else Readied.Png(out.toByteArray())
    } finally {
        bitmap.recycle()
    }
}

/** The picture at `uri` (the phone's clipboard's) readied to paste; off the main thread. */
fun readyImage(resolver: ContentResolver, uri: Uri): Readied {
    val bytes = try {
        resolver.openInputStream(uri)?.use { readAtMost(it, CLIP_SOURCE_MAX) ?: return Readied.TooLarge } ?: return Readied.Unreadable
    } catch (_: Exception) {
        return Readied.Unreadable
    }
    return asPng(bytes, ::encodePng)
}

/** The copies made on screens, kept in the cache while the phone's clipboard may point at them. */
object ScreenClips {
    /** How many are kept: the one on the clipboard and a couple before it (another app may still be reading one). */
    const val KEEP = 3

    /** Under the cache (the FileProvider's `screen-clips` path, res/xml/drive_files.xml). */
    fun dir(cache: File) = File(cache, "screen-clips")

    private var last = 0L

    /** `png` kept as a new file in `dir`, named so the newest sorts last; those beyond [KEEP] deleted, oldest first. */
    @Synchronized
    fun keep(dir: File, png: ByteArray, now: Long = System.currentTimeMillis()): File {
        dir.mkdirs()
        // Each later than the one before, however quickly they come.
        last = maxOf(now, last + 1)
        val file = File(dir, "copied-${last.toString().padStart(15, '0')}.png")
        file.writeBytes(png)
        val all = dir.listFiles()?.filter { it.isFile }?.sortedBy { it.name }.orEmpty()
        all.dropLast(KEEP).forEach { it.delete() }
        return file
    }
}
