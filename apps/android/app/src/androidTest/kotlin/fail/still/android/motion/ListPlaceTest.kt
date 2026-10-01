// The list's scroll place, left for a chat and come back to (Harness.kt; motion.sh runs it): the same rows show, in the
// middle of the list (also left by the back gesture) and at its end (where a first layout without the bars' heights
// clamped it short).
package fail.still.android.motion

import android.util.Log
import androidx.activity.BackEventCompat
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import fail.still.android.Screen
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class ListPlaceTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun item(i: Int) = ChatItem(
        id = "c$i", session = "ember:c-$i", thread = 100L + i, title = "row-$i", agents = emptyList(), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - i * 60_000L, station = Fixtures.STATION, stationName = "st",
    )

    private fun view(n: Int) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "st", "st", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until n).map(::item))),
    )

    /** The rows on screen, top to bottom. */
    private fun shown(h: Harness): List<String> {
        val nodes = rule.onAllNodesWithText("row-", substring = true).fetchSemanticsNodes()
        return nodes.filter { n -> n.boundsInRoot.bottom > 0 && n.boundsInRoot.top < rule.onRoot().fetchSemanticsNode().size.height }
            .mapNotNull { it.config.getOrNull(SemanticsProperties.Text)?.firstOrNull()?.text }
    }

    @Test fun middle() = keptComingBack(1, "mid")
    @Test fun end() = keptComingBack(4, "end")
    @Test fun middleSwipedBack() = keptComingBack(1, "mid-swiped", swipedBack = true)

    /** Back as the system's back gesture does it (predictive back: the page follows the finger, then let go). */
    private fun swipeBack(h: Harness) {
        val back = rule.activity.onBackPressedDispatcher
        val w = rule.activity.window.decorView.width.toFloat()
        rule.runOnUiThread { back.dispatchOnBackStarted(BackEventCompat(0f, 1000f, 0f, BackEventCompat.EDGE_LEFT)) }
        for (i in 1..10) { rule.runOnUiThread { back.dispatchOnBackProgressed(BackEventCompat(w * i / 20f, 1000f, i / 10f, BackEventCompat.EDGE_LEFT)) }; h.deliver() }
        rule.runOnUiThread { back.onBackPressed() }
    }

    private fun keptComingBack(swipes: Int, name: String, swipedBack: Boolean = false) {
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), view(40))
        h.fake.put(Topics.chats(Fixtures.WS, true), view(40))
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), view(0))
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home))
        Log.i("listplace", "start ${shown(h)}")
        repeat(swipes) { rule.onRoot().performTouchInput { swipeUp(startY = bottom * (if (swipes > 1) 0.8f else 0.7f), endY = bottom * (if (swipes > 1) 0.2f else 0.4f)) }; h.settle() }
        val before = shown(h)
        Log.i("listplace", "$name scrolled $before")
        h.record("$name-scrolled").also { it.frames(1); it.end() }
        rule.runOnUiThread { h.app.push(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))) }
        h.settle(); h.settle()
        if (swipedBack) swipeBack(h) else rule.runOnUiThread { h.app.pop() }
        h.settle(); h.settle()
        val after = shown(h)
        Log.i("listplace", "$name back $after")
        h.record("$name-back").also { it.frames(1); it.end() }
        check(before.firstOrNull() == after.firstOrNull()) { "place lost: before=$before after=$after" }
    }
}
