package dev.ember.android.screens

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons

fun openUrl(context: Context, url: String) = CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())

/** What the phone leaves to the computer: a line that opens the same place on ember's web page. */
@Composable
fun OnComputer(what: String, url: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Row(
        modifier.fillMaxWidth().clickable { openUrl(context, url) }.padding(horizontal = 24.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(what, fontSize = 13.sp, color = C.muted, modifier = Modifier.weight(1f))
        Text("在电脑上打开", fontSize = 13.sp, color = C.accent)
        IconIn(Icons.External, 14.dp, C.accent)
    }
}

/** A row of a picking sheet: what, a line under it, and a check on the chosen one. */
@Composable
fun PickRow(label: String, sub: String? = null, checked: Boolean = false, enabled: Boolean = true, color: Color = C.ink, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            leading?.invoke()
            Column(Modifier.weight(1f)) {
                Text(label, fontSize = 15.sp, color = if (enabled) color else C.subtle)
                if (sub != null) Text(sub, fontSize = 12.sp, color = C.muted)
            }
            if (checked) IconIn(Icons.Check, 14.dp, C.accent)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(C.line))
    }
}
