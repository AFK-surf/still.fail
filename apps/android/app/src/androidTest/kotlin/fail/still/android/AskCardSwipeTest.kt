// The ask card (screens/AskCard.kt) swiped with real touches, injected as a finger would give them: right says its
// delegate answer, left sets it aside; short of the threshold it springs back; up or down, a tap on a pill, a drag begun
// in its reply field are not swipes; a tap on it elsewhere shows the message that asked. First on the cards alone (AskCards, the callbacks), then in a chat's page as the
// app lays it out (over its messages, under the composer: what the fake core is asked).
package fail.still.android

import androidx.activity.ComponentActivity
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewGroup
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.ChatOf
import fail.still.android.data.Creator
import fail.still.android.data.Topics
import fail.still.android.data.WorkAnswer
import fail.still.android.data.WorkItem
import fail.still.android.motion.Fixtures
import fail.still.android.motion.Harness
import fail.still.android.motion.MotionRule
import fail.still.android.screens.AskCards
import fail.still.android.screens.AskLocal
import fail.still.android.ui.StillFailTheme
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class AskCardSwipeTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val now = System.currentTimeMillis()
    private val me = Creator(id = Fixtures.account.email, name = "Alice", via = "cloud")
    private fun said(title: String, a: String) = "「$title」$a"

    private val yes = WorkAnswer("准", "yes", said("设置页间距", "准"))
    private val option = WorkAnswer("先只改设置页", "option", said("设置页间距", "先只改设置页"))
    private val delegate = WorkAnswer("随便", "delegate", said("设置页间距", "随便"))
    private val gap = WorkItem(
        key = "gap", session = "ember:c-1", title = "设置页间距", state = "waiting", waitingOn = listOf(me), createdAt = now, updatedAt = now,
        mine = true, lead = "奏", line = "settings-gap · 前后对比在上面 14:02", evidence = 2,
        question = "间距这样改，合吗？", head = "奏 · 设置页间距 · 3 分钟前",
        answers = listOf(yes, option, delegate, WorkAnswer("待定", "defer")),
    )
    private val archive = WorkItem(
        key = "archive", session = "ember:c-1", title = "归档页时间往右挪一点", state = "waiting", waitingOn = listOf(me), createdAt = now, updatedAt = now,
        mine = true, lead = "奏", line = "archive-time · 3 分钟前",
        question = "归档页时间往右挪一点", head = "奏 · 归档页时间往右挪一点 · 3 分钟前",
        answers = listOf(WorkAnswer("准", "yes", said("归档页时间往右挪一点", "准")), WorkAnswer("随便", "delegate", said("归档页时间往右挪一点", "随便")), WorkAnswer("待定", "defer")),
    )

    private var answered: Pair<WorkItem, WorkAnswer>? = null
    private var deferred: WorkItem? = null
    private var replied: Pair<WorkItem, String>? = null
    private var shown: WorkItem? = null

    /** The cards alone, at the foot of the screen as over a chat's composer. */
    private fun cards() {
        rule.setContent {
            StillFailTheme(false) {
                Box(Modifier.fillMaxSize()) {
                    AskCards(
                        listOf(gap, archive), remember { AskLocal() }, remember { HazeState() },
                        // Clear of the system's gesture area at the foot (as over the composer).
                        Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp),
                        onAnswer = { i, a -> answered = i to a }, onDefer = { deferred = it }, onReply = { i, w -> replied = i to w }, onShow = { shown = it },
                    )
                }
            }
        }
        rule.waitForIdle()
    }

    /** The message that asked (gap's evidence), and enough after it that it is far above the end. */
    private val asked = "间距那三处，前后对比在上面"
    private val talk = listOf(Fixtures.mine(1, "侧栏底部那行和设置页的间距都不对"), Fixtures.agent(2, asked)) +
        (3L..40L).map { if (it % 2 == 0L) Fixtures.agent(it, "第 $it 条：继续改") else Fixtures.mine(it, "第 $it 条：好") }

    /** A chat's page as the app shows it, the cards over its messages. */
    private fun chat(): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(talk, title = "侧栏和设置的几处间距").copy(asks = listOf(gap, archive)))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        return h
    }

    private fun title(): Rect = rule.onNodeWithText(gap.question).fetchSemanticsNode().boundsInRoot
    private fun field(): Rect = rule.onNode(hasSetTextAction() and hasContentDescription("回复「${gap.title}」")).fetchSemanticsNode().boundsInRoot
    private val width get() = rule.onRoot().fetchSemanticsNode().size.width.toFloat()

    /**
     * A finger from `start` to `end` in `steps` moves, `stepMs` apart, a frame drawn after each (as on a phone: the card
     * has moved under the finger before its next move comes; one `swipe()` injects every move before any frame).
     */
    private fun drag(start: Offset, end: Offset, steps: Int = 12, stepMs: Long = 16) {
        if (viaSystem) return systemDrag(start, end, steps, stepMs)
        rule.mainClock.autoAdvance = false
        rule.onRoot().performTouchInput { down(start) }
        frame()
        for (k in 1..steps) {
            rule.onRoot().performTouchInput { moveTo(start + (end - start) * (k.toFloat() / steps), delayMillis = stepMs) }
            frame()
        }
        rule.onRoot().performTouchInput { up() }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
    }

    /**
     * Set: gestures go in as the system's own touches (UiAutomation, through the input dispatcher to the activity's
     * window, in real time), not straight into the compose view.
     */
    private var viaSystem = false

    private fun systemDrag(start: Offset, end: Offset, steps: Int, stepMs: Long) {
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        val at = IntArray(2)
        rule.runOnUiThread { rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0).getLocationOnScreen(at) }
        var t0 = SystemClock.uptimeMillis()
        fun send(action: Int, p: Offset): Boolean {
            val props = arrayOf(MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_FINGER })
            val coords = arrayOf(MotionEvent.PointerCoords().apply { x = p.x + at[0]; y = p.y + at[1]; pressure = 1f; size = 1f })
            val e = MotionEvent.obtain(t0, SystemClock.uptimeMillis(), action, 1, props, coords, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
            return ui.injectInputEvent(e, false).also { e.recycle() }
        }
        // A pointer left down by a gesture cut short (a failed test) would have every DOWN after it refused.
        send(MotionEvent.ACTION_CANCEL, start)
        Thread.sleep(50)
        t0 = SystemClock.uptimeMillis()
        check(send(MotionEvent.ACTION_DOWN, start)) { "DOWN not injected" }
        try {
            for (k in 1..steps) { Thread.sleep(stepMs); check(send(MotionEvent.ACTION_MOVE, start + (end - start) * (k.toFloat() / steps))) { "MOVE not injected" } }
            Thread.sleep(stepMs)
        } finally { check(send(MotionEvent.ACTION_UP, end)) { "UP not injected" } }
        Thread.sleep(50)
        rule.waitForIdle()
    }

    private fun systemTap(p: Offset) = systemDrag(p, p, 1, 40)

    private fun frame() { rule.waitForIdle(); rule.mainClock.advanceTimeByFrame(); rule.waitForIdle() }

    /** A finger across the screen at `y`, from `from` to `to` (shares of its width), quickly (~200 ms). */
    private fun across(y: Float, from: Float, to: Float) = drag(Offset(width * from, y), Offset(width * to, y))

    /** Short of the threshold (an eighth of the width), slowly: no fling. */
    private fun short(y: Float) = drag(Offset(width * 0.4f, y), Offset(width * 0.52f, y), steps = 20, stepMs = 25)

    /** Up the screen, a little sideways. */
    private fun up(at: Rect) = drag(Offset(width * 0.5f, at.center.y), Offset(width * 0.56f, at.center.y - 400f))

    /** Across from just inside the reply field's start. */
    private fun inField() = field().let { f -> drag(Offset(f.left + 30f, f.center.y), Offset(f.left + width * 0.7f, f.center.y)) }

    private fun settle() { rule.mainClock.advanceTimeBy(2000); rule.waitForIdle() }

    private fun assertNothing() {
        settle()
        assertNull("answered: $answered", answered); assertNull("deferred: $deferred", deferred); assertNull("replied: $replied", replied)
        assertNull("shown: $shown", shown)
    }

    private fun assertInPlace(before: Rect) {
        val after = title()
        assertTrue("card not back in place: $before -> $after", abs(after.left - before.left) < 1f && abs(after.top - before.top) < 1f)
    }

    // --- The cards alone ---

    @Test fun swipeRightSaysItsDelegateAnswer() {
        cards()
        across(title().center.y, 0.25f, 0.9f)
        rule.waitUntil(3000) { answered != null }
        assertEquals(gap.key, answered!!.first.key)
        assertEquals(delegate, answered!!.second)
        assertNull(deferred); assertNull(shown)
    }

    @Test fun swipeLeftSetsItAside() {
        cards()
        across(title().center.y, 0.75f, 0.1f)
        rule.waitUntil(3000) { deferred != null }
        assertEquals(gap.key, deferred!!.key)
        assertNull(answered)
    }

    @Test fun swipeBegunOnAPillIsStillASwipe() {
        cards()
        val pill = rule.onNodeWithText(option.label).fetchSemanticsNode().boundsInRoot
        drag(pill.center, Offset(pill.center.x + width * 0.6f, pill.center.y))
        rule.waitUntil(3000) { answered != null }
        assertEquals(delegate, answered!!.second)
    }

    @Test fun shortSlowSwipeSpringsBack() {
        cards()
        val before = title()
        short(before.center.y)
        assertNothing()
        assertInPlace(before)
    }

    @Test fun verticalSwipeIsNotASwipe() {
        cards()
        val before = title()
        up(before)
        assertNothing()
        assertInPlace(before)
    }

    @Test fun tapOnAPillAnswersIt() {
        cards()
        rule.onNodeWithText(option.label).performClick()
        rule.waitUntil(3000) { answered != null }
        assertEquals(option, answered!!.second)
        assertNull(deferred); assertNull(shown)
    }

    @Test fun tapElsewhereOnTheCardShowsWhatAsked() {
        cards()
        rule.onNodeWithText(gap.question).performClick()
        rule.waitUntil(3000) { shown != null }
        assertEquals(gap.key, shown!!.key)
        assertNull(answered); assertNull(deferred)
    }

    @Test fun dragInTheReplyFieldIsNotASwipe() {
        cards()
        val before = title()
        inField()
        assertNothing()
        assertInPlace(before)
    }

    // --- In a chat's page ---

    private fun Harness.called(name: String) = fake.calls.filter { it.first == name }

    @Test fun inChatSwipeRightAnswers() {
        val h = chat()
        across(title().center.y, 0.25f, 0.9f)
        h.settle()
        val calls = h.called("item.answer")
        assertEquals("calls: ${h.fake.calls.map { it.first }}", 1, calls.size)
        assertEquals(delegate.text, calls[0].second["answer"]!!.jsonPrimitive.content)
        assertEquals(gap.key, calls[0].second["key"]!!.jsonPrimitive.content)
    }

    @Test fun inChatSwipeLeftDefers() {
        val h = chat()
        across(title().center.y, 0.75f, 0.1f)
        h.settle()
        val calls = h.called("item.defer")
        assertEquals("calls: ${h.fake.calls.map { it.first }}", 1, calls.size)
        assertEquals(gap.key, calls[0].second["key"]!!.jsonPrimitive.content)
    }

    @Test fun inChatShortVerticalAndFieldDragsDoNothing() {
        val h = chat()
        val before = title()
        short(before.center.y)
        h.settle()
        assertInPlace(before)
        up(before)
        h.settle()
        assertInPlace(before)
        inField()
        h.settle()
        assertInPlace(before)
        val acted = h.fake.calls.filter { it.first == "item.answer" || it.first == "item.defer" }
        assertTrue("acted: $acted", acted.isEmpty())
    }

    @Test fun inChatTapShowsTheMessageThatAsked() {
        val h = chat()
        rule.onNodeWithText(asked).assertDoesNotExist()
        rule.onNodeWithText(gap.question).performClick()
        h.settle()
        rule.onNodeWithText(asked).assertIsDisplayed()
        val acted = h.fake.calls.filter { it.first == "item.answer" || it.first == "item.defer" }
        assertTrue("acted: $acted", acted.isEmpty())
    }

    @Test fun inChatTapOnAPillAnswers() {
        val h = chat()
        rule.onNodeWithText(option.label).performClick()
        h.settle()
        val calls = h.called("item.answer")
        assertEquals("calls: ${h.fake.calls.map { it.first }}", 1, calls.size)
        assertEquals(option.text, calls[0].second["answer"]!!.jsonPrimitive.content)
    }

    // --- As the system's touches (through the window) ---

    @Test fun systemSwipeRightSaysItsDelegateAnswer() { viaSystem = true; swipeRightSaysItsDelegateAnswer() }
    @Test fun systemSwipeLeftSetsItAside() { viaSystem = true; swipeLeftSetsItAside() }
    @Test fun systemShortSlowSwipeSpringsBack() { viaSystem = true; shortSlowSwipeSpringsBack() }
    @Test fun systemVerticalSwipeIsNotASwipe() { viaSystem = true; verticalSwipeIsNotASwipe() }
    @Test fun systemDragInTheReplyFieldIsNotASwipe() { viaSystem = true; dragInTheReplyFieldIsNotASwipe() }
    @Test fun systemTapOnAPillAnswersIt() {
        viaSystem = true
        cards()
        systemTap(rule.onNodeWithText(option.label).fetchSemanticsNode().boundsInRoot.center)
        rule.waitUntil(3000) { answered != null }
        assertEquals(option, answered!!.second)
    }
    @Test fun systemInChatSwipeRightAnswers() { viaSystem = true; inChatSwipeRightAnswers() }
    @Test fun systemInChatSwipeLeftDefers() { viaSystem = true; inChatSwipeLeftDefers() }
    @Test fun systemInChatTapShowsTheMessageThatAsked() {
        viaSystem = true
        val h = chat()
        rule.onNodeWithText(asked).assertDoesNotExist()
        systemTap(title().center)
        h.settle()
        rule.onNodeWithText(asked).assertIsDisplayed()
    }
    @Test fun systemInChatShortVerticalAndFieldDragsDoNothing() { viaSystem = true; inChatShortVerticalAndFieldDragsDoNothing() }
}
