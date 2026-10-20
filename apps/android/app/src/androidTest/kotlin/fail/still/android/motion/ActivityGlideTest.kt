// An agent's line at the end of its chat, a frame at a time (Harness.kt): pushed by a message coming in above it, it
// glides to its new place; the keyboard going or coming (where the test puts it) is not a push: the line goes with the
// chat, as far under the message above it every frame, and the end stays over the composer.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.MutableWindowInsets
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import fail.still.android.Screen
import fail.still.android.data.Activity
import fail.still.android.data.ActivityNow
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.Live
import fail.still.android.data.Session
import fail.still.android.data.Topics
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

@OptIn(ExperimentalLayoutApi::class)
class ActivityGlideTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val key = "ember:c-1"
    private val doing = "读取 deploy.yml"

    private val running = ChatAgent(
        session = Session(
            key = key, runtime = "claude", process = "running", pending = 0, statusText = "工作中", tone = "accent", titleText = "修一下登录",
            agentText = "Claude", maker = Fixtures.anthropic, runtimeText = "Claude Code", efforts = listOf("high"),
        ),
        status = "running", profiles = emptyList(), choices = emptyList(), attention = emptyList(),
        since = System.currentTimeMillis() - 2_000, turns = emptyList(), threads = emptyList(), jobs = emptyList(),
    )

    /** Long enough to scroll, so the list is at its end with more above it. */
    private val history: List<ChatMessage> = (1L..24L).map {
        if (it % 2 == 1L) Fixtures.mine(it, "第 $it 条：部署前再检查一下登录页") else Fixtures.agent(it, "第 $it 条：好，我先看一下 deploy.yml 里的配置")
    }

    private val keyboard = MutableWindowInsets(WindowInsets(0, 0, 0, 0))
    private fun keyboardAt(px: Int) = rule.runOnUiThread { keyboard.insets = WindowInsets(0, 0, 0, px) }

    private fun bounds(text: String): Rect = rule.onAllNodes(hasText(text), useUnmergedTree = true)[0].fetchSemanticsNode().boundsInRoot
    private fun composerTop(): Float = rule.onAllNodes(hasSetTextAction())[0].fetchSemanticsNode().boundsInRoot.top

    /** Per frame: how far the agent's line is under the last message, and how far its foot is over the composer. */
    private class Seen { val gaps = ArrayList<Float>(); val ends = ArrayList<Float>() }

    private fun Seen.look() {
        val line = bounds(doing)
        gaps += line.top - bounds(history.last().text).bottom
        ends += composerTop() - line.bottom
    }

    private fun open(h: Harness, keyboardFrom: Int) {
        h.fake.put(Topics.live(Fixtures.STATION, key), Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = Activity(ActivityNow(key = "read", text = doing))))
        h.fake.put(topic, Fixtures.chat(history).copy(agents = listOf(running)))
        keyboardAt(keyboardFrom)
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))), keyboard = keyboard)
        h.settle()
    }

    private fun moves(name: String, from: Int, to: Int) {
        val h = Harness(rule)
        open(h, from)
        val seen = Seen()
        val r = h.record(name)
        seen.look()
        // As the system moves it: quick at first, slowing to its place.
        val steps = 18
        for (i in 1..steps) {
            val f = i / steps.toFloat()
            val eased = 1f - (1f - f) * (1f - f) * (1f - f)
            r.frame { keyboardAt((from + (to - from) * eased).toInt()) }
            seen.look()
        }
        repeat(20) { r.frame(); seen.look() }
        r.end()
        val gap = seen.gaps.first()
        val end = seen.ends.first()
        seen.gaps.forEachIndexed { i, g -> assertTrue("frame $i: the agent's line ${g - gap}px off its place under the message above (gaps ${seen.gaps})", abs(g - gap) <= 1f) }
        seen.ends.forEachIndexed { i, e -> assertTrue("frame $i: the end ${e - end}px off its place over the composer (ends ${seen.ends})", abs(e - end) <= 1f) }
    }

    /** A message said while it works comes in above it: it glides down under it, not put there at once. */
    @Test
    fun pushedGlides() {
        val h = Harness(rule)
        open(h, 0)
        val above = history.last().text
        val gaps = ArrayList<Float>()
        val r = h.record("pushed-glides")
        gaps += bounds(doing).top - bounds(above).bottom
        r.frame { h.fake.put(topic, Fixtures.chat(history + Fixtures.mine(25, "顺便把 Safari 也测一下", System.currentTimeMillis() + 60_000, said = true)).copy(agents = listOf(running))) }
        h.deliver()
        repeat(40) { r.frame(); gaps += bounds(doing).top - bounds(above).bottom }
        r.end()
        val from = gaps.first()
        val to = gaps.last()
        assertTrue("pushed down (gaps $gaps)", to - from > 40f)
        val between = gaps.count { it > from + 2f && it < to - 2f }
        assertTrue("glided, $between frames on the way (gaps $gaps)", between >= 4)
    }

    @Test
    fun keyboardGoes() = moves("keyboard-goes", 900, 0)

    @Test
    fun keyboardComes() = moves("keyboard-comes", 0, 900)
}
