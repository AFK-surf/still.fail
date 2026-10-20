// A drive's folders and files as the pages show and name them (the drive's own, a station's page, a chat's files, a
// screen's drops). Here, below the pages, so that the pages, the drive and the screens do not depend on each other
// (2026-10-17).
package fail.still.android.data

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns

/**
 * A folder's entries as shown, as the web's (web/src/drive/order.ts): hidden ones (a name starting with `.`) left out
 * unless asked, folders first, then by name (the station's order), time or size (the newest and largest first) or kind;
 * `-down` turns it the other way.
 */
fun arranged(entries: List<DriveEntry>, sort: String, hidden: Boolean): List<DriveEntry> {
    val by = sort.substringBefore('-')
    val down = sort.endsWith("-down")
    val shown = if (hidden) entries else entries.filterNot { it.name.startsWith('.') }
    val named = entries.withIndex().associate { it.value.name to it.index }
    val byName = compareBy<DriveEntry> { named[it.name] ?: 0 }
    val order: Comparator<DriveEntry> = when (by) {
        "time" -> compareByDescending<DriveEntry> { it.mtime }.then(byName)
        "size" -> compareByDescending<DriveEntry> { it.size }.then(byName)
        "kind" -> compareBy<DriveEntry>({ it.kind.toString() }, { it.name.substringAfterLast('.', "").lowercase() }).then(byName)
        else -> byName
    }
    return shown.sortedWith(compareBy<DriveEntry> { !it.dir }.then(if (down) order.reversed() else order))
}

/** What the station page's row says of a drive: how many folders it lends, or that it lends none. */
fun driveValue(roots: List<DriveRoot>): String = if (roots.isEmpty()) t("android-misc.drive.row.none") else t("android-misc.drive.roots.count", "n" to roots.size)

/** A name not among `taken`: "name (1).ext", "name (2).ext"… */
fun freeName(name: String, taken: Set<String>): String {
    if (name !in taken) return name
    val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
    val stem = name.substring(0, dot)
    val ext = name.substring(dot)
    var n = 1
    while ("$stem ($n)$ext" in taken) n++
    return "$stem ($n)$ext"
}

/** A picked document's name and size, as its provider says. */
fun picked(resolver: ContentResolver, uri: Uri): Pair<String, Long> {
    var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    var size = -1L
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
        if (c.moveToFirst()) {
            c.getString(0)?.let { name = it }
            if (!c.isNull(1)) size = c.getLong(1)
        }
    }
    return name to size
}
