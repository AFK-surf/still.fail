// The usage page's days (settings/Usage.kt Days) on the fake core: the day picked said over the bars (today at first),
// each day's bar split by who it was for, and with several people what each spent that day under the days; a day
// tapped says its own. Pictures: motion/usage-chart-{one,several}-{light,dark}, motion/usage-chart-picked-light.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.Topics
import fail.still.android.data.UsageDay
import fail.still.android.data.UsageList
import fail.still.android.data.UsageSeries
import fail.still.android.data.UsageTick
import fail.still.android.data.UsageTile
import fail.still.android.data.UsageView
import org.junit.Rule
import org.junit.Test

class UsageChartTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    // a week as one person's usage page had it (2026-10-23): the most on 10/20
    private val week = listOf("10/17" to 1395.0, "10/18" to 1223.0, "10/19" to 3884.0, "10/20" to 5351.0, "10/21" to 2100.0, "10/22" to 1741.0, "10/23" to 1156.0)
    private val splits = listOf(listOf(.62, .28, .10), listOf(.55, .33, .12), listOf(.7, .22, .08), listOf(.5, .4, .1), listOf(.6, .25, .15), listOf(.66, .24, .1), listOf(.58, .3, .12))
    private fun money(v: Double) = "$" + "%,d".format(Math.round(v))

    private fun view(several: Boolean): UsageView {
        val series = if (several) listOf(UsageSeries("a@x", "你"), UsageSeries("b@x", "Ana"), UsageSeries("", "其他")) else listOf(UsageSeries("a@x", "你"))
        val daily = week.mapIndexed { i, (label, cost) ->
            val parts = if (several) splits[i].map { it * cost } else listOf(cost)
            UsageDay("2026-${label.replace("/", "-")}", label, i == week.size - 1, cost, money(cost), cost * 9.0, "${"%,d".format(Math.round(cost * 9.0))} 次调用", parts, parts.map(::money))
        }
        return UsageView(
            7u, Fixtures.NO_WAIT, false, listOf(UsageTile("折合费用", "≥$16,850", "按 API 价算"), UsageTile("模型调用", "15.7 万次", "日均 2.2 万次")),
            series, daily, 5351.0, 6000.0, listOf(UsageTick(2000.0, "2k"), UsageTick(4000.0, "4k"), UsageTick(6000.0, "6k")),
            listOf(UsageList("people", "按人", emptyList())), emptyList(), "按各家 API 价折算",
        )
    }

    private fun launch(several: Boolean, dark: Boolean): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.usage(Fixtures.WS, 7), view(several))
        h.launch(listOf(Screen.Usage), dark)
        h.settle()
        return h
    }

    private fun shot(h: Harness, name: String) = h.record(name).also { it.frames(1); it.end() }

    @Test fun oneLight() = pictures(false, false)
    @Test fun oneDark() = pictures(false, true)
    @Test fun severalLight() = pictures(true, false)
    @Test fun severalDark() = pictures(true, true)

    private fun pictures(several: Boolean, dark: Boolean) {
        val h = launch(several, dark)
        // today at first: its cost and calls over the bars
        rule.onNodeWithText("$1,156").assertExists()
        rule.onNodeWithText("10,404 次调用").assertExists()
        if (several) rule.onNodeWithText("Ana").assertExists()
        shot(h, "usage-chart-" + (if (several) "several" else "one") + "-" + (if (dark) "dark" else "light"))
    }

    /** A day tapped says its own numbers, and with several people its own parts. */
    @Test fun aDayTapped() {
        val h = launch(true, false)
        rule.onNodeWithTag("usage-day-2026-10-20").performClick()
        h.settle()
        rule.onNodeWithText("$5,351").assertExists()
        rule.onNodeWithText(money(5351.0 * .4)).assertExists()
        shot(h, "usage-chart-picked-light")
    }
}
