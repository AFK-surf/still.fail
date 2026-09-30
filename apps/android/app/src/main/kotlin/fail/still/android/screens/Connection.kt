// How the connection is, over the top of a chat (the web's Connection.tsx): a frosted capsule, one line, only while
// something is not as it should be (connecting, catching up, down), and a moment after it is again.
package fail.still.android.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.LocalApp
import fail.still.android.data.LinkShown
import fail.still.android.data.StatusView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.floating
import fail.still.core.CoreException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private enum class PillTone { Busy, Trouble, Back }

private data class PillShown(val tone: PillTone, val text: String, val detail: String? = null)

/** How long "已连上" stays once all is well again. */
private const val BACK_MS = 1500L

/**
 * What is not as it should be with the link to this chat's station, or with what the core waits on (its `status`: what,
 * how long, how fast): nothing while all is well. Down, it offers to try again at once (no more waiting, the
 * connections tried against new ones: client/core/src/wake.rs `retry`); back, it says so a moment.
 */
@Composable
fun ConnectionPill(connection: LinkShown?, haze: HazeState, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val status by rememberTopic<StatusView>(app.core, Topics.status)
    val now = shownOf(connection, status.value)
    var back by remember { mutableStateOf(false) }
    var was by remember { mutableStateOf(false) }
    LaunchedEffect(now != null) {
        if (now != null) {
            was = true
            back = false
        } else if (was) {
            was = false
            back = true
            delay(BACK_MS)
            back = false
        }
    }
    val shown = now ?: if (back) PillShown(PillTone.Back, "已连上") else null
    val scope = rememberCoroutineScope()
    AnimatedVisibility(shown != null, modifier, enter = fadeIn(), exit = fadeOut()) {
        val s = shown ?: PillShown(PillTone.Back, "已连上")
        val shape = RoundedCornerShape(50)
        Row(
            Modifier.widthIn(max = 360.dp).height(30.dp).floating(haze, shape).padding(start = 12.dp, end = if (s.tone == PillTone.Trouble) 4.dp else 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            when (s.tone) {
                PillTone.Busy -> Spinner(12.dp)
                PillTone.Trouble -> Box(Modifier.size(6.dp).clip(CircleShape).background(C.red))
                PillTone.Back -> Box(Modifier.size(6.dp).clip(CircleShape).background(C.muted))
            }
            val color = when (s.tone) { PillTone.Trouble -> C.red; PillTone.Back -> C.muted; PillTone.Busy -> C.ink }
            Text(s.text, color = color, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            s.detail?.let { Text(it, color = C.muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)) }
            if (s.tone == PillTone.Trouble) {
                Box(
                    Modifier.height(22.dp).clip(RoundedCornerShape(50)).background(C.chip).clickable {
                        scope.launch {
                            try {
                                // A person's retry (client/core/src/wake.rs): `network` for a core from before `retry`.
                                app.core.call("client.wake", buildJsonObject { put("away", 0); put("network", true); put("retry", true) })
                            } catch (_: CoreException) {
                            }
                        }
                    }.padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center,
                ) { Text("重试", color = C.ink, fontSize = 13.sp) }
            }
        }
    }
}

/** The chat's link as the core says it (its `connection`) while down or coming back, else what the core waits on. */
private fun shownOf(connection: LinkShown?, status: StatusView?): PillShown? = when {
    connection != null -> PillShown(if (connection.tone == "trouble") PillTone.Trouble else PillTone.Busy, connection.text, connection.detail)
    status?.state == "trouble" -> PillShown(PillTone.Trouble, status.text ?: "连不上 still.fail cloud")
    status?.state == "slow" -> PillShown(PillTone.Busy, status.text ?: "")
    else -> null
}
