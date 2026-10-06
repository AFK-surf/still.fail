// The account, as the narrow web has it (web/src/mobile/Me.tsx), from the card atop settings (SettingsHome.kt): who is
// signed in, the accounts on this device, and where it is signed in.
package fail.still.android.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.Account
import fail.still.android.data.Auth
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.data.t
import kotlinx.coroutines.launch

@Composable
fun MeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val me = current.account
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("android-settings.me.title"))
        Card {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Avatar(me.email, me.name.ifEmpty { me.email }, 46.dp, picture = me.picture)
                Column {
                    Text(me.name.ifEmpty { me.email }, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink)
                    Text("${me.email} · Google", fontSize = 13.sp, color = C.muted)
                }
            }
        }
        val list = accounts.value.orEmpty()
        // Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added.
        SectionHeader(t("android-settings.me.accounts"), start = 24.dp)
        ListCard {
            list.forEach { a ->
                ListRow {
                    Text(a.email, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    // Signing out: home at once, the sign-out going on by itself (a toast if it could not); not asked twice meanwhile.
                    if (app.isDoing("auth.signOut", "account" to a.sub)) Spinner(14.dp)
                    else Text(if (list.size > 1) t("android-settings.me.signOut") else t("android-settings.me.signOutOnly"), fontSize = 15.sp, color = C.red, modifier = Modifier.clickable {
                        app.home()
                        app.act(t("android-settings.me.signOutWhat"), if (list.size > 1) t("android-settings.me.signedOut", "email" to a.email) else null) { Auth.signOut(app.core, a.sub) }
                    })
                }
            }
            val opening = app.isDoing("auth.begin")
            ListRow(onClick = if (opening) null else ({ scope.launch { signIn(app, context) } })) {
                Text(t("android-settings.me.addAccount"), fontSize = 15.sp, color = C.accent, modifier = Modifier.weight(1f))
                if (opening) Spinner(14.dp)
            }
        }
        SectionHeader(t("android-settings.me.devices"), start = 24.dp)
        Devices(current)
        Spacer(Modifier.height(30.dp))
    }
}
