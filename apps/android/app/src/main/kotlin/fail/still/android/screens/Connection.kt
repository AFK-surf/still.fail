// 重试 for a connection down (the web's Connection.tsx): the connections tried again at once.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.ui.C
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** 重试 as a small grey pill: the connections tried again at once. On a station down, where it is tried again (Stations.kt). */
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
