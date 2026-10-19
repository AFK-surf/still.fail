// A subscription's sign-in on its Profile page (Profiles.kt SignIn, LoginSteps), on the fake core: signed in (重新登录),
// signed out (登录), a device code to approve (Grok) and a code to paste back (Claude). Pictures:
// motion/signin-{signed-in,needed,grok-code,claude-code}-{light,dark}.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import fail.still.android.Screen
import fail.still.android.data.Access
import fail.still.android.data.Counts
import fail.still.android.data.LoginJob
import fail.still.android.data.Overview
import fail.still.android.data.Profile
import fail.still.android.data.ProfileCheck
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import org.junit.Rule
import org.junit.Test

class ProfileSignInTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun profile(runtime: String, check: String, login: LoginJob? = null) = Profile(
        id = "p1", name = if (runtime == "grok") "SuperGrok" else "zzj-max", runtime = runtime, runtimes = listOf(runtime),
        access = Access(kind = "subscription", key = ""), home = "/Users/alice/.stillfail/profiles/p1", homeExists = true,
        models = emptyList(), env = emptyList(), usedBy = emptyList(),
        loginCommand = if (runtime == "grok") "grok login --device-auth" else "claude /login",
        check = ProfileCheck(state = check, detail = if (check == "ok") "可用，Claude Max" else "需要登录", checkedAt = Fixtures.NOW),
        login = login, checkText = if (check == "ok") "可用" else "需要登录", checkTone = if (check == "ok") "green" else "amber",
        makers = emptyMap(), names = emptyMap(), series = emptyList(), modelsText = "",
    )

    private fun job(runtime: String, state: String) = LoginJob(
        profile = "p1", runtime = runtime, state = state,
        url = if (runtime == "grok") "https://accounts.x.ai/device" else "https://claude.ai/oauth/authorize?code=true",
        userCode = if (state == "needs_approval") "QXRT-7KMB" else null, startedAt = Fixtures.NOW, expiresAt = Fixtures.NOW + 600_000,
    )

    private fun shot(p: Profile, name: String, dark: Boolean): Harness {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home, Screen.Profile(Fixtures.STATION, p.id)), dark)
        val station = Fixtures.station.copy(overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = listOf(p), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
        ))
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        h.record("signin-$name-" + if (dark) "dark" else "light").also { it.frame(); it.end() }
        return h
    }

    @Test fun signedInLight() = signedIn(false)
    @Test fun signedInDark() = signedIn(true)
    private fun signedIn(dark: Boolean) {
        shot(profile("claude", "ok"), "signed-in", dark)
        rule.onNodeWithText("重新登录").assertIsDisplayed()
    }

    @Test fun neededLight() = needed(false)
    @Test fun neededDark() = needed(true)
    private fun needed(dark: Boolean) {
        shot(profile("claude", "login"), "needed", dark)
        rule.onNodeWithText("登录").assertIsDisplayed()
    }

    @Test fun grokCodeLight() = grokCode(false)
    @Test fun grokCodeDark() = grokCode(true)
    private fun grokCode(dark: Boolean) {
        shot(profile("grok", "login", job("grok", "needs_approval")), "grok-code", dark)
        rule.onNodeWithText("QXRT-7KMB").assertIsDisplayed()
        rule.onNodeWithText("复制代码并打开登录页").assertIsDisplayed()
        rule.onNodeWithText("取消登录").assertIsDisplayed()
    }

    @Test fun claudeCodeLight() = claudeCode(false)
    @Test fun claudeCodeDark() = claudeCode(true)
    private fun claudeCode(dark: Boolean) {
        shot(profile("claude", "login", job("claude", "needs_code")), "claude-code", dark)
        rule.onAllNodesWithText("打开授权页面", substring = true)[0].assertIsDisplayed()
        rule.onNodeWithText("完成").assertIsDisplayed()
        rule.onNodeWithText("取消登录").assertIsDisplayed()
    }
}
