// 外观 › 字体 (the web phone's mobile/Fonts.tsx): each place's face (ui/Fonts.kt), picked from the app's own and those
// still.fail keeps; one picked is fetched (its size said before, how far while it comes) and the app is set in it once
// it is here. The preview above the list is the three as the app is set now.
package fail.still.android.screens

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.FontFace
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.CodeFont
import fail.still.android.ui.FaceFiles
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.PickRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.TextFont

private val PLACES = listOf("ui", "text", "code")

private fun placeLabel(place: String) = t("web-pages.appearance.fonts.$place")
private fun noneLabel(place: String) = t(if (place == "text") "web-pages.appearance.fonts.followUi" else "web-pages.appearance.fonts.default")

/** 外观's rows: each place and its face, opening its page. */
@Composable
fun FontRows() {
    val app = LocalApp.current
    val faces = app.kept.faces
    SectionHeader(t("web-pages.appearance.fonts.title"), start = 24.dp)
    ListCard {
        for (place in PLACES) {
            val chosen = app.fontChosen(place)
            val face = when (place) { "ui" -> faces?.ui; "text" -> faces?.text; else -> faces?.code }
            GoRow(placeLabel(place), if (chosen == null) noneLabel(place) else face?.name ?: chosen) { app.push(Screen.Fonts(place)) }
        }
    }
}

@Composable
fun FontsScreen(place: String) {
    val app = LocalApp.current
    val context = LocalContext.current
    val chosen = app.fontChosen(place)
    val list = app.kept.faces?.list.orEmpty().filter { it.mono == (place == "code") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.appearance.title"), app::pop)
        LargeTitle("", placeLabel(place))
        FontPreview()
        ListCard {
            PickRow(noneLabel(place), checked = chosen == null) { app.setFont(place, null) }
            for (face in list) {
                val fetching = FaceFiles.fetching[face.id]
                val failed = FaceFiles.failed[face.id]
                val here = FaceFiles.family(face) != null
                val sub = when {
                    fetching != null -> t("android-settings.fonts.downloading", "percent" to (fetching * 100).toInt())
                    failed != null -> t("android-settings.fonts.failed", "error" to failed)
                    here -> null
                    else -> t("android-settings.fonts.download", "size" to Formatter.formatShortFileSize(context, face.bytes))
                }
                PickRow(face.name, sub = sub, checked = chosen == face.id, busy = fetching != null && chosen == face.id) { pick(app, place, face) }
            }
        }
        Text(t("web-pages.appearance.fonts.description"), fontSize = 13.sp, lineHeight = 19.5.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp))
        Spacer(Modifier.height(30.dp))
    }
}

/** Picked: kept as chosen (fetched as the app follows it, ui/Fonts.kt rememberFonts); one that failed, fetched again. */
private fun pick(app: fail.still.android.AppState, place: String, face: FontFace) {
    FaceFiles.failed.remove(face.id)
    app.setFont(place, face.id)
}

private const val CODE_SAMPLE = "const font = { code: \"maple-mono\" };\n// 0O 1lI {}[] => != 注释"

/** The three as the app is set in them now (the web's FontSetting.tsx FontPreview). */
@Composable
private fun FontPreview() {
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(placeLabel("ui"), fontSize = 12.sp, color = C.subtle)
                Text(t("web-pages.appearance.fonts.sampleUi"), fontSize = 15.sp, color = C.ink)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(placeLabel("text"), fontSize = 12.sp, color = C.subtle)
                Text(t("web-pages.appearance.fonts.sampleText"), fontSize = 15.sp, lineHeight = 24.sp, color = C.ink, fontFamily = TextFont)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(placeLabel("code"), fontSize = 12.sp, color = C.subtle)
                // Without a ground of its own: nothing drawn in the card's corners.
                Text(CODE_SAMPLE, fontSize = 12.5.sp, lineHeight = 19.sp, color = C.ink, fontFamily = CodeFont)
            }
        }
    }
}
