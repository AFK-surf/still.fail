// ＋ in a composer: the gallery's recent photos across the top, a tap putting one in the message (most of what goes to
// an agent is a screenshot just taken), the camera before them; under them the system's photo picker, its file picker
// and (where there is one) Station 文件. The recent photos need the gallery's permission, asked for from the strip's
// last tile (on Android 14 and later the photos chosen there may be all it gets: the tile then chooses more); without
// it the strip is the camera and that tile. The phone's web cannot read a gallery: there ＋ is a menu (mobile/Chat.tsx).
package fail.still.android.screens

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import fail.still.android.ui.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import fail.still.android.AppState
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What ＋ offers: the system's camera, photo and file pickers, a recent photo of the gallery's put in, and asking for the gallery. */
class Attach(
    val camera: () -> Unit,
    val photos: () -> Unit,
    val files: () -> Unit,
    val recent: (Uri) -> Unit = {},
    val askPhotos: () -> Unit = {},
    /** Counts the gallery's answers, for the strip to read it again after one. */
    val answered: MutableIntState = mutableIntStateOf(0),
)

/** How much of the gallery the app may read: all of it, the photos chosen for it (Android 14 and later), or none. */
enum class PhotoAccess { All, Some, None }

fun photoAccess(context: Context): PhotoAccess {
    fun has(p: String) = ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED
    return when {
        has(if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE) -> PhotoAccess.All
        Build.VERSION.SDK_INT >= 34 && has(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> PhotoAccess.Some
        else -> PhotoAccess.None
    }
}

private val galleryAsk: Array<String> get() = when {
    Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

@Composable
fun AttachLaunchers(onPicked: (Picked) -> Unit): Attach {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap -> bitmap?.let { onPicked(photoPicked(it)) } }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    val answered = remember { mutableIntStateOf(0) }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { answered.intValue++ }
    return remember {
        Attach(
            camera = { camera.launch(null) },
            photos = { photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            files = { files.launch(arrayOf("*/*")) },
            recent = { uri -> scope.launch { readPicked(context, uri)?.let(onPicked) } },
            askPhotos = {
                // Asked and turned down for good (the system shows no dialog any more): the app's settings, where it is allowed.
                val prefs = context.getSharedPreferences("stillfail", Context.MODE_PRIVATE)
                val activity = context as? Activity
                val refused = prefs.getBoolean(ASKED, false) && photoAccess(context) == PhotoAccess.None &&
                    activity != null && galleryAsk.none { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
                if (refused) context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                else { prefs.edit().putBoolean(ASKED, true).apply(); gallery.launch(galleryAsk) }
            },
            answered = answered,
        )
    }
}

private const val ASKED = "attach.gallery.asked"
private const val RECENT = 30
/** A recent photo's tile, for the tests. */
const val RECENT_TAG = "attach-recent"
private val TILE_W = 92.dp
private val TILE_H = 122.dp

/** ＋'s sheet: the recent photos, then 照片, 文件 and (`station`) Station 文件. As tall as those two rows. */
fun openAttach(app: AppState, attach: Attach, station: (() -> Unit)? = null) {
    app.sheet = SheetSpec(0.32f, fit = 25.dp + 4.dp + TILE_H + 12.dp + 70.dp + 18.dp) {
        SheetGrab()
        RecentPhotos(app, attach)
        Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOfNotNull(
                Triple(t("android-chat.attach.photos"), Icons.Photo, attach.photos),
                Triple(t("android-chat.attach.files"), Icons.File, attach.files),
                station?.let { Triple(t("web-pages.chat.files"), Icons.Server, it) },
            ).forEach { (label, icon, go) ->
                // Its name under its icon, the tile's whole width for it (Station files, on a phone set to show things large).
                Column(
                    Modifier.weight(1f).height(70.dp).clip(Smooth(14.dp)).background(C.chip).clickable { app.sheet = null; go() }.padding(horizontal = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
                ) {
                    IconIn(icon, 22.dp)
                    Text(label, fontSize = 13.sp, lineHeight = 18.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun RecentPhotos(app: AppState, attach: Attach) {
    val context = LocalContext.current
    // Read again on each answer of the gallery's, and as the sheet opens (allowed meanwhile in the system's settings).
    val access = remember(attach.answered.intValue) { photoAccess(context) }
    var photos by remember { mutableStateOf(emptyList<Uri>()) }
    LaunchedEffect(access, attach.answered.intValue) { photos = if (access == PhotoAccess.None) emptyList() else recentPhotos(context) }
    LazyRow(
        Modifier.fillMaxWidth(), contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item(key = "camera") { Tile({ app.sheet = null; attach.camera() }) { IconIn(Icons.Camera, 24.dp) } }
        items(photos, key = { it.toString() }) { uri -> Tile({ app.sheet = null; attach.recent(uri) }, Modifier.testTag(RECENT_TAG)) { Thumbnail(uri) } }
        if (access != PhotoAccess.All) item(key = "ask") {
            val words = if (access == PhotoAccess.Some) t("android-chat.attach.recent.more") else t("android-chat.attach.recent.allow")
            Tile(attach.askPhotos) { Words(Icons.Photo, words) }
        }
    }
}

@Composable
private fun Tile(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.size(TILE_W, TILE_H).clip(Smooth(14.dp)).background(C.chip).clickable(onClick = onClick), contentAlignment = Alignment.Center) { content() }
}

@Composable
private fun Words(icon: ImageVector, words: String) {
    Column(Modifier.padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        IconIn(icon, 22.dp, C.muted)
        Text(words, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, textAlign = TextAlign.Center)
    }
}

@Composable
private fun Thumbnail(uri: Uri) {
    val context = LocalContext.current
    val picture by produceState<ImageBitmap?>(null, uri) { value = thumbnail(context, uri) }
    picture?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
}

private suspend fun thumbnail(context: Context, uri: Uri): ImageBitmap? = withContext(Dispatchers.IO) {
    try { context.contentResolver.loadThumbnail(uri, Size(276, 366), null).asImageBitmap() } catch (_: Exception) { null }
}

/**
 * The gallery's latest photos, as many as it lets the app read. Not as the gallery sorts them: what it says of when a
 * photo came may be wrong (written in milliseconds, or ahead of now, by an app saving a picture or a phone maker's own
 * gallery and cloud), and that put old photos ahead of every screenshot since. Each photo's times are read (added,
 * changed, taken) and the latest believable one of them ranks it (`latest`).
 */
private suspend fun recentPhotos(context: Context): List<Uri> = withContext(Dispatchers.IO) {
    val from = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    val columns = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_ADDED, MediaStore.Images.Media.DATE_MODIFIED, MediaStore.Images.Media.DATE_TAKEN)
    val photos = try {
        context.contentResolver.query(from, columns, null, null, null)?.use { c ->
            fun at(i: Int) = if (c.isNull(i)) null else c.getLong(i)
            buildList { while (c.moveToNext()) add(GalleryPhoto(c.getLong(0), at(1), at(2), at(3)?.let { it / 1000 })) }
        } ?: emptyList()
    } catch (_: SecurityException) { emptyList() }
    latest(photos, System.currentTimeMillis() / 1000, RECENT).map { ContentUris.withAppendedId(from, it) }
}

/** A photo of the gallery's and what it says of when, each in seconds (as it says them: perhaps wrong). */
class GalleryPhoto(val id: Long, val added: Long?, val modified: Long?, val taken: Long?)

/**
 * The ids of the `n` photos latest at `now` (seconds), newest first: each by the latest of its times that can be
 * believed, a time in milliseconds taken as the seconds it means and one still ahead of now (by more than a day) left
 * out; the gallery's own order (its id) between photos of the same time.
 */
fun latest(photos: List<GalleryPhoto>, now: Long, n: Int): List<Long> {
    fun believed(t: Long?): Long? {
        val s = t?.let { if (it > 100_000_000_000L) it / 1000 else it } ?: return null
        return s.takeIf { it in 1..(now + 86_400) }
    }
    return photos.asSequence()
        .map { p -> p.id to (listOfNotNull(believed(p.added), believed(p.modified), believed(p.taken)).maxOrNull() ?: 0L) }
        .sortedWith(compareByDescending<Pair<Long, Long>> { it.second }.thenByDescending { it.first })
        .take(n).map { it.first }.toList()
}
