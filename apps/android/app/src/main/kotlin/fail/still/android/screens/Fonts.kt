// 外观 › 字体 (the web phone's mobile/Fonts.tsx, the wide screen's FontSetting.tsx): the three places one at a time, a
// chat as their faces set it, and the faces of the place in view, each drawn in itself (its preview, ui/Fonts.kt,
// fetched at once) with a line of it under its name. One picked is fetched whole (its size said before, how far while
// it comes); the preview shows it at once, the app once it is here.
package fail.still.android.screens

import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.FontFace
import fail.still.android.data.t
import fail.still.android.ui.AppFonts
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.FaceFiles
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.JetBrainsMono
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.LocalFonts
import fail.still.android.ui.Markdown
import fail.still.android.ui.Seg
import fail.still.android.ui.Smooth

private val PLACES = listOf("ui", "text", "code")

private fun placeLabel(place: String) = t("web-pages.appearance.fonts.$place")
private fun noneLabel(place: String) = t(if (place == "text") "web-pages.appearance.fonts.followUi" else "web-pages.appearance.fonts.default")

/** 外观's row: the three faces at a glance, opening the page. */
@Composable
fun FontRow() {
    val app = LocalApp.current
    val faces = app.kept.faces
    val names = PLACES.filter { app.fontChosen(it) != null }.map { when (it) { "ui" -> faces?.ui; "text" -> faces?.text; else -> faces?.code }?.name.orEmpty() }
    GoRow(t("web-pages.appearance.fonts.title"), if (names.isEmpty()) t("web-pages.appearance.fonts.default") else names.joinToString(" · ")) { app.push(Screen.Fonts) }
}

/** A face as far as it is here: whole, else its preview; null, the app's own. */
private fun shownFamily(face: FontFace?): FontFamily? = face?.let { FaceFiles.family(it) ?: FaceFiles.previews[it.id] }

@Composable
fun FontsScreen() {
    val app = LocalApp.current
    val context = LocalContext.current
    var at by rememberSaveable { mutableIntStateOf(0) }
    val place = PLACES[at]
    val chosen = app.fontChosen(place)
    val faces = app.kept.faces
    val all = faces?.list.orEmpty()
    // Every face's preview, at once: each is shown in itself.
    LaunchedEffect(all.map { it.id }) { for (f in all) FaceFiles.fetchPreview(f) }
    FaceFiles.fetched
    val list = all.filter { it.mono == (place == "code") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.appearance.title"), app::pop)
        LargeTitle("", t("web-pages.appearance.fonts.title"))
        Seg(PLACES.map(::placeLabel), at, { at = it }, Modifier.padding(horizontal = 12.dp).fillMaxWidth(), height = 34.dp, fill = true)
        Spacer(Modifier.height(12.dp))
        // As chosen, each place in its face as far as it is here (a face being fetched: its preview).
        val ui = shownFamily(faces?.ui.takeIf { app.fontChosen("ui") != null })
        val text = shownFamily(faces?.text.takeIf { app.fontChosen("text") != null }) ?: ui
        val code = shownFamily(faces?.code.takeIf { app.fontChosen("code") != null }) ?: JetBrainsMono
        FontPreview(AppFonts(ui, text, code))
        ListCard {
            FaceRow(noneLabel(place), null, place, chosen == null, null) { app.setFont(place, null) }
            for (face in list) {
                val fetching = FaceFiles.fetching[face.id]
                val failed = FaceFiles.failed[face.id]
                val status = when {
                    fetching != null -> t("android-settings.fonts.downloading", "percent" to (fetching * 100).toInt())
                    failed != null -> t("android-settings.fonts.failed", "error" to failed)
                    FaceFiles.family(face) != null -> null
                    else -> Formatter.formatShortFileSize(context, face.bytes)
                }
                FaceRow(face.name, face, place, chosen == face.id, status, failed != null) {
                    FaceFiles.failed.remove(face.id)
                    app.setFont(place, face.id)
                }
            }
            // One installed on a computer, chosen there (prefs are this device's: not one of this phone's).
        }
        Text(t("web-pages.appearance.fonts.description"), fontSize = 13.sp, lineHeight = 19.5.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp))
        Spacer(Modifier.height(30.dp))
    }
}

/** A face: its name and a line of it, each in itself (none: the app's own for the place); at its end, how it stands. */
@Composable
private fun FaceRow(name: String, face: FontFace?, place: String, checked: Boolean, status: String?, bad: Boolean = false, onClick: () -> Unit) {
    val family = shownFamily(face) ?: when (place) {
        "code" -> JetBrainsMono
        // Text none chosen: as the interface is now.
        "text" -> LocalFonts.current.ui
        else -> null
    }
    ListRow(onClick = onClick) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, fontSize = 16.sp, color = C.ink, fontFamily = family, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(t("web-pages.appearance.fonts.sampleRow"), fontSize = 13.sp, color = C.muted, fontFamily = family, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (status != null) Text(status, fontSize = 12.sp, color = if (bad) C.red else C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 140.dp))
        if (checked) IconIn(Icons.Check, 14.dp, C.accent)
    }
}

private const val CODE_SAMPLE = "```ts\nform.onsubmit = (e) => {\n  e.preventDefault(); // 0O 1lI\n};\n```"

/** A chat as `fonts` set it (the web's FontPreview): their message in its bubble, an agent's under its name. */
@Composable
private fun FontPreview(fonts: AppFonts) {
    val style = LocalTextStyle.current
    CompositionLocalProvider(LocalFonts provides fonts, LocalTextStyle provides if (fonts.ui == null) style else style.copy(fontFamily = fonts.ui)) {
        Card {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    Text(t("web-pages.appearance.fonts.sampleMine"), fontSize = 15.sp, lineHeight = 21.sp, color = C.ink, fontFamily = fonts.text,
                        modifier = Modifier.clip(Smooth(18.dp)).background(C.bg).padding(horizontal = 14.dp, vertical = 8.dp))
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Claude", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.accentInk)
                        Text(t("web-pages.appearance.fonts.sampleTime"), fontSize = 12.sp, color = C.subtle)
                    }
                    Markdown("${t("web-pages.appearance.fonts.sampleText")}\n\n$CODE_SAMPLE\n\n${t("web-pages.appearance.fonts.sampleAfter")}", size = 15)
                }
            }
        }
    }
}
