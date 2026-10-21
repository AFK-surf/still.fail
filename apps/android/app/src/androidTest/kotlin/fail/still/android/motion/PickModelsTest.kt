// The step right after a profile is added (Profiles.kt PickModelsScreen), on the fake core: its models still being read
// (the station's first check not back), and listed by series with one enabled. Pictures:
// motion/pick-models-{reading,listed}-{light,dark}.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import fail.still.android.Screen
import fail.still.android.data.Access
import fail.still.android.data.Counts
import fail.still.android.data.ModelSeries
import fail.still.android.data.Overview
import fail.still.android.data.Profile
import fail.still.android.data.ProfileCheck
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import org.junit.Rule
import org.junit.Test

class PickModelsTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val names = mapOf(
        "swe-2" to "SWE-2", "claude-opus-5-5" to "Opus 5.5", "claude-sonnet-5-5" to "Sonnet 5.5", "claude-fable-5-1" to "Fable 5.1",
        "gpt-6-astra" to "GPT-6 Astra", "gpt-6-1-sol" to "GPT-6.1 Sol", "gpt-6-luna" to "GPT-6 Luna", "glm-5-3" to "GLM-5.3", "kimi-k3" to "Kimi K3",
    )

    private fun profile(reading: Boolean) = Profile(
        id = "p1", name = "zzj@acme.dev", runtime = "devin", runtimes = listOf("devin"),
        access = Access(kind = "subscription", key = ""), home = "/Users/alice/.stillfail/profiles/p1", homeExists = true,
        models = if (reading) emptyList() else listOf("swe-2"), env = emptyList(), usedBy = emptyList(), loginCommand = "devin auth login",
        check = if (reading) null else ProfileCheck(state = "ok", detail = "已登录", models = names.keys.toList(), checkedAt = Fixtures.NOW),
        checkText = if (reading) "未检查" else "可用", checkTone = if (reading) "neutral" else "green",
        makers = emptyMap(), names = if (reading) emptyMap() else names, modelsText = "",
        series = if (reading) emptyList() else listOf(
            ModelSeries("Fable", listOf("claude-fable-5-1")), ModelSeries("Opus", listOf("claude-opus-5-5")), ModelSeries("Sonnet", listOf("claude-sonnet-5-5")),
            ModelSeries("Astra", listOf("gpt-6-astra")), ModelSeries("Sol", listOf("gpt-6-1-sol")), ModelSeries("Luna", listOf("gpt-6-luna")),
            ModelSeries("其他", listOf("glm-5-3", "kimi-k3", "swe-2")),
        ),
        available = if (reading) emptyList() else names.keys.toList(), modelsReading = reading,
    )

    private fun shot(p: Profile, name: String, dark: Boolean) {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home, Screen.PickModels(Fixtures.STATION, p.id)), dark)
        val station = Fixtures.station.copy(overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = listOf(p), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
        ))
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        h.record("pick-models-$name-" + if (dark) "dark" else "light").also { it.frame(); it.end() }
    }

    @Test fun readingLight() = reading(false)
    @Test fun readingDark() = reading(true)
    private fun reading(dark: Boolean) {
        shot(profile(true), "reading", dark)
        rule.onNodeWithText("正在读取可用模型").assertIsDisplayed()
        rule.onNodeWithText("完成").assertIsNotEnabled()
    }

    @Test fun listedLight() = listed(false)
    @Test fun listedDark() = listed(true)
    private fun listed(dark: Boolean) {
        shot(profile(false), "listed", dark)
        rule.onNodeWithText("GPT-6.1 Sol").assertIsDisplayed()
        rule.onNodeWithText("完成").assertIsEnabled()
    }
}
