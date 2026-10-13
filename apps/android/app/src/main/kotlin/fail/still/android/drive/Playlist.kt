// What plays after what in a folder of a drive, and which subtitle goes with a video (zdrive's Playlist.kt and
// SideSubtitles.kt): plain functions over names, checked on the JVM (src/test PlaylistTest, SideSubtitlesTest).
package fail.still.android.drive

/** The playable names of a folder in the order a person would watch them: numbers as numbers (E2 before E10). */
fun playlistOf(names: List<String>, playable: (String) -> Boolean): List<String> = names.filter(playable).distinct().sortedWith(::compareNatural)

/** What follows `current` in `list`, or null at its end; one missing from the list still has a place by its name. */
fun nextIn(current: String, list: List<String>): String? {
    val at = list.indexOf(current)
    return if (at >= 0) list.getOrNull(at + 1) else list.firstOrNull { compareNatural(it, current) > 0 }
}

/** Names with their numbers compared as numbers: `E2` before `E10`. */
fun compareNatural(a: String, b: String): Int {
    var i = 0
    var j = 0
    while (i < a.length && j < b.length) {
        val ca = a[i]
        val cb = b[j]
        if (ca.isDigit() && cb.isDigit()) {
            val startA = i
            val startB = j
            while (i < a.length && a[i].isDigit()) i++
            while (j < b.length && b[j].isDigit()) j++
            val numA = a.substring(startA, i).trimStart('0')
            val numB = b.substring(startB, j).trimStart('0')
            if (numA.length != numB.length) return numA.length - numB.length
            val digits = numA.compareTo(numB)
            if (digits != 0) return digits
        } else {
            val chars = ca.lowercaseChar().compareTo(cb.lowercaseChar())
            if (chars != 0) return chars
            i++
            j++
        }
    }
    val rest = (a.length - i) - (b.length - j)
    return if (rest != 0) rest else a.compareTo(b)
}

/** Best first: `.srt` is what such files usually come with. */
private val SUBTITLE_EXTENSIONS = listOf("srt", "vtt", "ass", "ssa")

/**
 * The subtitle for the video `base`, out of the names beside it: `<base>.<ext>` or `<stem>.<ext>` (E01.srt for E01.mp4)
 * first, then one with a tag between (`E01.zh.srt`), the whole name winning a tie.
 */
fun pickSubtitle(base: String, names: List<String>): String? {
    val stems = listOf(base, base.substringBeforeLast('.', base)).distinct()
    return names.mapNotNull { name ->
        val stem = stems.firstOrNull { name.startsWith("$it.", ignoreCase = true) } ?: return@mapNotNull null
        val extension = name.substringAfterLast('.').lowercase()
        val rank = SUBTITLE_EXTENSIONS.indexOf(extension)
        if (rank < 0) return@mapNotNull null
        val tag = name.substring(stem.length)
        Candidate(name, exact = tag.length == extension.length + 1, full = stem == base, rank, tag)
    }.minWithOrNull(compareBy({ !it.exact }, { !it.full }, { it.rank }, { it.tag }))?.name
}

private data class Candidate(val name: String, val exact: Boolean, val full: Boolean, val rank: Int, val tag: String)

/** A speed as it is shown: 1×, 1.5×, 0.75×. */
fun speedLabel(speed: Float): String = "${speed.toString().removeSuffix(".0")}×"

/** `m:ss`, or `h:mm:ss` past an hour. */
fun clock(ms: Long): String {
    val total = (ms.coerceAtLeast(0) + 500) / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
