// How the connection is, over the top of a chat (the web's Connection.tsx): a frosted capsule, one line, only while
// something is not as it should be (connecting, catching up, down), and a moment after it is again; when, the core says.
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.LocalApp
import fail.still.android.data.ConnectionView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.floating
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * What a chat on `station` says of its connection, as the core decides it (its `connection` topic, client/core/src/pill.rs):
 * its link down or coming back, or what its workspace's core waits on (what, how long, how fast), and only once that
 * has lasted; "已连上" a moment after. Nothing while all is well, nothing of another workspace. Down, it offers to try
 * again at once (no more waiting, the connections tried against new ones: client/core/src/wake.rs `retry`).
 */
@Composable
fun ConnectionPill(station: String, haze: HazeState, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val connection by rememberTopic<ConnectionView>(app.core, Topics.connection(station))
    val shown = connection.value?.takeIf { it.tone != null }
    AnimatedVisibility(shown != null, modifier, enter = fadeIn(), exit = fadeOut()) {
        // Going, it was "已连上" (what comes after a busy or a trouble shown).
        val s = shown ?: ConnectionView(tone = "back", text = "已连上", items = emptyList())
        val shape = RoundedCornerShape(50)
        val trouble = s.tone == "trouble"
        Row(
            Modifier.widthIn(max = 360.dp).height(30.dp).floating(haze, shape).padding(start = 12.dp, end = if (trouble) 4.dp else 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            when (s.tone) {
                "busy" -> Spinner(12.dp)
                "trouble" -> Box(Modifier.size(6.dp).clip(CircleShape).background(C.red))
                else -> Box(Modifier.size(6.dp).clip(CircleShape).background(C.muted))
            }
            val color = when (s.tone) { "trouble" -> C.red; "busy" -> C.ink; else -> C.muted }
            Text(s.text.orEmpty(), color = color, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            s.detail?.let { Text(it, color = C.muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)) }
            if (trouble) RetryPill()
        }
    }
}

/** 重试 as a small grey pill: the connections tried again at once. Here and on a station down, where it is tried again (Stations.kt). */
@Composable
fun RetryPill(modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    Box(
        modifier.height(22.dp).clip(RoundedCornerShape(50)).background(C.chip).clickable {
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
