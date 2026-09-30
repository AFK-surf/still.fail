// You, as the narrow web has it (web/src/mobile/Me.tsx): who is signed in, which accounts, how it looks, where it is
// signed in, and this build (workspaces are switched from their name on Home).
package fail.still.android.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.ui.text.style.TextOverflow
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.BuildConfig
import fail.still.android.LocalApp
import fail.still.android.Push
import fail.still.android.rememberNotificationAsk
import fail.still.android.data.Account
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.Auth
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.entries
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.core.CoreException
import kotlinx.coroutines.launch

@Composable
fun MeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val me = current.account
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("会话", app::pop)
        LargeTitle("设置", "我")
        Card {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Avatar(me.email, me.name.ifEmpty { me.email }, 46.dp, picture = me.picture)
                Column {
                    Text(me.name.ifEmpty { me.email }, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink)
                    Text("${me.email} · Google", fontSize = 13.sp, color = C.muted)
                }
            }
        }
        // Workspaces are switched from their name on Home (Workspaces.kt), as on the web.
        val list = accounts.value.orEmpty()
        SectionHeader("外观", start = 24.dp)
        val themes = listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色")
        Seg(themes.map { it.second }, themes.indexOfFirst { it.first == app.theme }.coerceAtLeast(0), { app.useTheme(themes[it].first) },
            Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth(), height = 36.dp, fill = true)
        // Whose pictures lead a chat's row in the list (RowPicture.kt).
        SectionHeader("列表头像", start = 24.dp)
        val pictures = listOf("auto" to "自动", "agents" to "Agent 为主", "people" to "人为主")
        Seg(pictures.map { it.second }, pictures.indexOfFirst { it.first == app.rowPicture }.coerceAtLeast(0), { app.useRowPicture(pictures[it].first) },
            Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth(), height = 36.dp, fill = true)
        // Local notices and pushes alike, on this device (Notices.kt, Push.kt); turned on, the system is asked too.
        SectionHeader("通知", start = 24.dp)
        val ask = rememberNotificationAsk(app, once = false)
        ListCard {
            ListRow(onClick = {
                val on = !app.notify
                app.useNotify(on)
                if (on) ask()
                scope.launch { Push.sync(context.applicationContext, app.core, on) }
            }) {
                Column(Modifier.weight(1f)) {
                    Text("通知", fontSize = 15.sp, color = C.ink)
                    Text(if (app.notify) "你参与的会话有新消息、需要处理或出错时通知你。" else "不会收到通知。", fontSize = 13.sp, color = C.muted)
                }
                Switch(app.notify)
            }
        }
        SectionHeader("登录的地方", start = 24.dp)
        Devices(current)
        // Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added.
        SectionHeader("账号", start = 24.dp)
        ListCard {
            list.forEach { a ->
                ListRow {
                    Text(a.email, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text(if (list.size > 1) "退出" else "退出登录", fontSize = 15.sp, color = C.red, modifier = Modifier.clickable {
                        scope.launch {
                            try {
                                Auth.signOut(app.core, a.sub)
                                app.home()
                                if (list.size > 1) app.toast = "已退出 ${a.email}"
                            } catch (e: CoreException) {
                                app.toast = "没能退出：${e.message}"
                            }
                        }
                    })
                }
            }
            ListRow(onClick = { scope.launch { signIn(app, context) } }) {
                Text("＋ 登录另一个 Google 账号", fontSize = 15.sp, color = C.accent)
            }
        }
        // This build, and a newer one when still.fail cloud has it: tapped, it is downloaded and installed.
        SectionHeader("版本", start = 24.dp)
        val updates = app.updates
        val newer = updates.available
        LaunchedEffect(Unit) { app.checkUpdates() }
        ListCard {
            ListRow(onClick = if (newer == null || updates.progress != null) null else ({ scope.launch { updates.install()?.let { app.toast = it } } })) {
                Text("still.fail ${BuildConfig.VERSION_NAME}", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                Text(updates.progress ?: newer?.let { "更新到 ${it.versionName}" } ?: "已是最新", fontSize = 15.sp, color = if (newer != null && updates.progress == null) C.accent else C.muted)
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}
