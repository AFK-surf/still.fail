package fail.still.android.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons


/**
 * Where what someone set going shows how it is (AppState.isDoing / failedOf): a spinner while it is under way, a small
 * red mark the few seconds after it failed (a tap says why), nothing otherwise. The menu or sheet that asked may be gone.
 */
@Composable
fun DoingMark(running: Boolean, failed: String?, size: Dp = 14.dp) {
    val app = LocalApp.current
    if (running) Spinner(size)
    else if (failed != null) IconIn(Icons.Info, size, C.red, Modifier.semantics { contentDescription = failed }.clickable { app.toast = failed })
}

/**
 * A row of a picking sheet: what, a line under it, and a check on the chosen one; `busy`: what it set going is under way
 * (a spinner, not tapped again); `failed`: it failed a moment ago (DoingMark).
 */
@Composable
fun PickRow(label: String, sub: String? = null, checked: Boolean = false, enabled: Boolean = true, busy: Boolean = false, failed: String? = null, color: Color = C.ink, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled && !busy, onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            leading?.invoke()
            Column(Modifier.weight(1f)) {
                Text(label, fontSize = 15.sp, color = if (enabled) color else C.subtle)
                if (sub != null) Text(sub, fontSize = 12.sp, color = C.muted)
            }
            if (busy || failed != null) DoingMark(busy, failed)
            else if (checked) IconIn(Icons.Check, 14.dp, C.accent)
        }
    }
}
