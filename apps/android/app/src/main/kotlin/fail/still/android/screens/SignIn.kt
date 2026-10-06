package fail.still.android.screens

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import fail.still.android.AppState
import fail.still.android.BuildConfig
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.data.Auth
import fail.still.android.ui.C
import fail.still.android.ui.Illustration
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Starts a Google sign-in through still.fail cloud in a Custom Tab; MainActivity finishes it when stillfail://auth/callback comes back. */
suspend fun signIn(app: AppState, context: Context) {
    try {
        val url = Auth.begin(app.core)
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())
    } catch (e: CoreException) {
        app.toast = t("android-settings.signIn.beginFailed", "error" to e.message)
    }
}

/** A dev cloud (cloud/test/dev.ts) signs its users in without Google: alice (its admin, with a workspace) or bob (let in by nothing yet), through the core (`dev.signIn`). */
private val DEV_CLOUD = Regex("^http://(127\\.0\\.0\\.1|localhost|10\\.0\\.2\\.2):\\d+$")

private suspend fun devSignIn(app: AppState, user: String) {
    try {
        app.core.call("dev.signIn", buildJsonObject { put("user", user) })
    } catch (e: CoreException) {
        app.toast = t("android-settings.signIn.failed", "error" to e.message)
    }
}

@Composable
fun SignInScreen() {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var asked by remember { mutableStateOf(false) }
    val busy = asked || app.isDoing("auth.begin")
    // A dev account signing in (DEBUG against a dev cloud only).
    var dev by remember { mutableStateOf<String?>(null) }
    Column(
        Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.systemBars).padding(horizontal = 30.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    ) {
        Illustration(R.drawable.illus_sign_in, R.drawable.illus_sign_in_dark, 300.dp)
        Text(t("android-settings.signIn.title"), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.5).sp, modifier = Modifier.padding(top = 10.dp))
        Text(t("android-settings.signIn.note"), color = C.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Row(
            Modifier.fillMaxWidth().height(50.dp).clip(CircleShape).background(C.ink)
                .clickable(enabled = !busy) { asked = true; scope.launch { signIn(app, context); asked = false } },
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
        ) {
            GoogleDot()
            Text(if (busy) t("android-settings.signIn.opening") else t("android-settings.signIn.google"), color = C.bg, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(t("android-settings.signIn.many"), color = C.muted, fontSize = 12.sp)
        if (BuildConfig.DEBUG && DEV_CLOUD.matches(app.cloudOrigin)) {
            Row {
                for (user in listOf("alice", "bob")) Text(if (dev == user) t("android-settings.signIn.signingIn") else t("android-settings.signIn.dev", "user" to user), color = C.accent, fontSize = 14.sp,
                    modifier = Modifier.clickable(enabled = dev == null) { dev = user; scope.launch { try { devSignIn(app, user) } finally { dev = null } } }.padding(8.dp))
            }
        }
    }
}

/** Google's "G", on white as Google asks for it on a dark button. */
@Composable
private fun GoogleDot() {
    Box(Modifier.size(24.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.google_g), contentDescription = null, modifier = Modifier.size(16.dp))
    }
}

