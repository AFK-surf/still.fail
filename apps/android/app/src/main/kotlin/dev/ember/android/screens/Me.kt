// You: who is signed in, which accounts and workspaces, how it looks.
package dev.ember.android.screens

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
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.LocalApp
import dev.ember.android.data.Account
import dev.ember.android.data.AccountWorkspaces
import dev.ember.android.data.Auth
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.entries
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.Card
import dev.ember.android.ui.LargeTitle
import dev.ember.android.ui.ListCard
import dev.ember.android.ui.ListRow
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.Seg
import dev.ember.core.CoreException
import kotlinx.coroutines.launch

@Composable
fun MeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val workspaces by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
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
        // One line per workspace: the name gives way with an ellipsis; which account it is under shows only when there are several.
        val list = accounts.value.orEmpty()
        SectionHeader("Workspace", start = 24.dp)
        ListCard {
            workspaces.value?.entries().orEmpty().forEach { e ->
                ListRow(onClick = { app.pickWorkspace(e.workspace.id); app.home() }) {
                    Column(Modifier.weight(1f)) {
                        Text(e.workspace.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (list.size > 1) Text(e.account.email, fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (e.workspace.id == current.workspace.id) IconIn(Icons.Check, 14.dp, C.accent)
                }
            }
        }
        SectionHeader("外观", start = 24.dp)
        val themes = listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色")
        Seg(themes.map { it.second }, themes.indexOfFirst { it.first == app.theme }.coerceAtLeast(0), { app.useTheme(themes[it].first) },
            Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth(), height = 36.dp, fill = true)
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
        Spacer(Modifier.height(30.dp))
    }
}
