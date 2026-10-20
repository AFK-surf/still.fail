// A long paste goes with the message as a text file, not into the composer (web/src/pastedText.ts): the field stays
// quick, and the agent reads it whole from the file.
package fail.still.android.screens

import java.util.UUID

/** Pasted at once, this many characters or more go as a file. */
internal const val PASTE_THRESHOLD = 5_000
/** A file of pasted text this long at most can be put back into the composer. */
internal const val PASTE_RESTORE_LIMIT = 25_000

/** Text pasted as a file: its first line (of its first 200 characters), how long, and itself. */
class PastedText(val text: String) {
    val preview: String = text.take(200).trim().split(Regex("\\r?\\n")).firstOrNull().orEmpty()
    val characters: Int get() = text.length
    /** It can be put back into the composer (not too long for it). */
    val restorable: Boolean get() = text.length <= PASTE_RESTORE_LIMIT
}

/** The file it goes as: `pasted-text-<uuid>.txt`, in UTF-8, as the web names it. */
internal fun pastedPicked(pasted: PastedText): Picked =
    Picked("pasted-text-${UUID.randomUUID()}.txt", pasted.text.toByteArray(Charsets.UTF_8), null, null, null)
