// 重试 for a connection down (the web's Connection.tsx): the connections tried again at once.
package fail.still.android.screens

import fail.still.android.ui.t
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.C

/**
 * 重试 as a small grey pill: the connections tried again at once, a spinner in it until the core has. On a station down,
 * where it is tried again (Stations.kt).
 */
@Composable
fun RetryPill(modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val trying = app.isDoing("client.wake")
    Row(
        modifier.height(22.dp).clip(RoundedCornerShape(50)).background(C.chip).clickable(enabled = !trying) {
            // A person's retry (client/core-ts/src/wake.ts): `network` for a core from before `retry`.
            app.act(t("android-misc.connection.reconnect")) { app.core.call("client.wake", buildJsonObject { put("away", 0); put("network", true); put("retry", true) }) }
        }.padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (trying) Spinner(10.dp)
        Text(t("common.retry"), color = C.ink, fontSize = 13.sp)
    }
}
