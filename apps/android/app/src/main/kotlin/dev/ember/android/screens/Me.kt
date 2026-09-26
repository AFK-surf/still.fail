// You: who is signed in, which accounts and workspaces, how it looks.
package dev.ember.android.screens

import androidx.compose.foundation.isSystemInDarkTheme
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
import dev.ember.android.ui.Toggle
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
                Avatar(me.email, me.name.ifEmpty { me.email }, 46.dp)
                Column {
                    Text(me.name.ifEmpty { me.email }, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink)
                    Text("${me.email} · Google", fontSize = 13.sp, color = C.muted)
                }
            }
        }
        SectionHeader("账号与 workspace", start = 24.dp)
        ListCard {
            val entries = workspaces.value?.entries().orEmpty()
            entries.forEach { e ->
                ListRow(onClick = { app.pickWorkspace(e.workspace.id); app.home() }) {
                    Text(e.workspace.name, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                    Text(e.account.email, fontSize = 13.sp, color = C.muted)
                }
            }
            ListRow(onClick = { scope.launch { signIn(app, context) } }) {
                Text("＋ 登录另一个 Google 账号", fontSize = 15.sp, color = C.accent)
            }
        }
        SectionHeader("外观", start = 24.dp)
        ListCard {
            ListRow {
                Text("深色模式", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                val system = isSystemInDarkTheme()
                Toggle(app.dark ?: system) { app.useDark(it) }
            }
        }
        // Signing out is per account, as on the web; with one account it is just 退出登录.
        ListCard {
            val list = accounts.value.orEmpty()
            list.forEach { a ->
                ListRow(onClick = {
                    scope.launch {
                        try {
                            Auth.signOut(app.core, a.sub)
                            app.home()
                            if (list.size > 1) app.toast = "已退出 ${a.email}"
                        } catch (e: CoreException) {
                            app.toast = "没能退出：${e.message}"
                        }
                    }
                }) { Text(if (list.size > 1) "退出 ${a.email}" else "退出登录", fontSize = 15.sp, color = C.red) }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}
