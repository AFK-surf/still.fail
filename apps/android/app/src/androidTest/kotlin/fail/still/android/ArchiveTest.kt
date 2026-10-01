// Archiving a chat with nothing left in it, with real touches injected as the system's own (UiAutomation, as in
// DecisionsTest), on the app over a fake core: on the home list an archivable row swiped left past the threshold is
// archived (chat.archive) and leaves; short of it, it springs back; up or down is the list's (it scrolls); a tap opens
// the chat; a row that cannot be archived does not move; its 归档 chip archives it too. In a chat that can be archived,
// 归档这个 chat under the agent's last all-done post archives it. `shots` pictures them (light) into files/shots.
package fail.still.android

import android.graphics.Bitmap
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onRoot
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.RowAgent
import fail.still.android.data.RowMessage
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.motion.Fixtures
import fail.still.android.motion.Harness
import fail.still.android.motion.MotionRule
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ArchiveTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun row(id: String, title: String, last: String, stateText: String? = null, tone: String? = null, settled: Boolean = false) = ChatItem(
        id = id, session = id, thread = null, title = title,
        agents = listOf(RowAgent(key = id, runtime = "claude", process = "idle", pending = 0, agentText = "Claude", maker = Fixtures.anthropic, statusText = "空闲")),
        last = RowMessage(seq = 1, authorKind = "agent", author = id, text = last, createdAt = Fixtures.NOW, preview = last),
        unread = false, mine = true, lastActiveAt = Fixtures.NOW, station = Fixtures.STATION, stationName = "studio",
        settled = if (settled) true else null, archivable = if (settled) true else null, stateText = stateText, tone = tone,
    )

    private val busy = row("ember:c-1", "侧栏和设置的几处间距", "在改", stateText = "在等：CI 跑完", tone = "wait")
    private val done = row("ember:c-2", "README 里的命令", "改好了，已推到 main", stateText = "做完了", settled = true)
    private val alsoDone = row("ember:c-3", "换掉旧的图标", "都换好了", stateText = "做完了", settled = true)
    private val rest = (4..14).map { row("ember:c-$it", "第 $it 件事", "还在做", stateText = "在等：Alice 看截图") }

    private fun chats(items: List<ChatItem>) = ChatsView(
        me = fail.still.android.data.Me(id = Fixtures.account.email), stations = listOf(StationState(Fixtures.STATION, "st", "studio", "online")),
        loading = false, days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", items)),
    )

    private fun putChats(h: Harness, items: List<ChatItem>) {
        val v = chats(items)
        h.fake.put(Topics.chats(Fixtures.WS, false), v)
        h.fake.put(Topics.chats(Fixtures.WS, true), v)
    }

    /** The list; archiving a row takes it out of the list, as the core would. */
    private fun home(): Harness {
        val h = Harness(rule)
        var items = listOf(busy, done, alsoDone) + rest
        putChats(h, items)
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats(emptyList()))
        h.fake.answer = { name, params ->
            if (name == "chat.archive") {
                val session = params["session"]!!.jsonPrimitive.content
                items = items.filter { it.session != session }
                putChats(h, items)
            }
            JsonNull
        }
        h.launch(listOf(Screen.Home))
        return h
    }

    // ── injected touches (DecisionsTest) ──

    private val width get() = rule.onRoot().fetchSemanticsNode().size.width.toFloat()
    /** Where `text` is on screen; none when it is not (the page keeps a copy of the list composed out of sight, of no size). */
    private fun at(text: String): Rect? = rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().map { it.boundsInRoot }.firstOrNull { it.width > 0f }
    private fun bounds(text: String): Rect = at(text)!!
    private fun shown(text: String) = at(text) != null

    private var origin: IntArray? = null
    private fun at(p: Offset): Offset {
        val o = origin ?: IntArray(2).also { a ->
            rule.runOnUiThread { rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0).getLocationOnScreen(a) }
            origin = a
        }
        return Offset(p.x + o[0], p.y + o[1])
    }

    private var downAt = 0L
    private fun send(action: Int, p: Offset): Boolean {
        val q = at(p)
        val props = arrayOf(MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_FINGER })
        val coords = arrayOf(MotionEvent.PointerCoords().apply { x = q.x; y = q.y; pressure = 1f; size = 1f })
        val e = MotionEvent.obtain(downAt, SystemClock.uptimeMillis(), action, 1, props, coords, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
        return InstrumentationRegistry.getInstrumentation().uiAutomation.injectInputEvent(e, true).also { e.recycle() }
    }

    private fun press(p: Offset) {
        send(MotionEvent.ACTION_CANCEL, p); Thread.sleep(50)
        downAt = SystemClock.uptimeMillis()
        check(send(MotionEvent.ACTION_DOWN, p)) { "DOWN not injected" }
    }

    private fun move(from: Offset, to: Offset, steps: Int, stepMs: Long) {
        for (k in 1..steps) { Thread.sleep(stepMs); check(send(MotionEvent.ACTION_MOVE, from + (to - from) * (k.toFloat() / steps))) { "MOVE not injected" } }
    }

    private fun release(p: Offset) { Thread.sleep(16); check(send(MotionEvent.ACTION_UP, p)) { "UP not injected" }; Thread.sleep(50); rule.waitForIdle() }

    private fun drag(start: Offset, end: Offset, steps: Int = 12, stepMs: Long = 16) {
        press(start)
        try { move(start, end, steps, stepMs) } finally { release(end) }
    }

    private fun tap(p: Offset) = drag(p, p, 1, 40)

    private fun Harness.archived() = fake.calls.filter { it.first == "chat.archive" }

    private fun assertArchived(h: Harness, session: String) {
        h.settle()
        val calls = h.archived()
        assertEquals("calls: $calls", 1, calls.size)
        assertEquals(session, calls[0].second["session"]!!.jsonPrimitive.content)
        assertEquals(true, calls[0].second["archived"]!!.jsonPrimitive.boolean)
    }

    // ── the list ──

    @Test fun swipeLeftArchives() {
        val h = home()
        val y = bounds(done.title).center.y
        drag(Offset(width * 0.8f, y), Offset(width * 0.15f, y))
        assertArchived(h, done.session)
        h.settle(2000)
        assertTrue("still listed", !shown(done.title))
        assertTrue("the next row gone too", shown(alsoDone.title))
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
    }

    @Test fun flingLeftArchives() {
        val h = home()
        val y = bounds(done.title).center.y
        // Under a third of the width, fast: archived though short of the threshold.
        drag(Offset(width * 0.75f, y), Offset(width * 0.45f, y), steps = 6, stepMs = 12)
        assertArchived(h, done.session)
    }

    @Test fun shortSwipeSpringsBack() {
        val h = home()
        val before = bounds(done.title)
        drag(Offset(width * 0.6f, before.center.y), Offset(width * 0.45f, before.center.y), steps = 20, stepMs = 25)
        h.settle(2000)
        assertTrue("archived: ${h.archived()}", h.archived().isEmpty())
        val after = bounds(done.title)
        assertTrue("not back: $before -> $after", abs(after.left - before.left) < 1f && abs(after.top - before.top) < 1f)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
    }

    @Test fun verticalScrollsTheList() {
        val h = home()
        val before = bounds(done.title)
        drag(Offset(width * 0.6f, before.center.y + 400f), Offset(width * 0.5f, before.center.y - 200f), steps = 16)
        h.settle(2000)
        assertTrue("archived: ${h.archived()}", h.archived().isEmpty())
        val after = at(done.title)
        // Scrolled up (or off the top), not moved across.
        assertTrue("not scrolled: $before -> $after", after == null || after.top < before.top - 100f)
        if (after != null) assertTrue("moved across: $after", abs(after.left - before.left) < 1f)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
    }

    @Test fun tapOpensTheChat() {
        val h = home()
        tap(Offset(width * 0.4f, bounds(done.title).center.y))
        h.settle()
        assertTrue("archived: ${h.archived()}", h.archived().isEmpty())
        val top = h.app.stack.last()
        assertTrue("opened: ${h.app.stack}", top is Screen.Chat && top.station == Fixtures.STATION)
    }

    @Test fun rowThatCannotBeArchivedDoesNotMove() {
        val h = home()
        val before = bounds(busy.title)
        press(Offset(width * 0.8f, before.center.y))
        move(Offset(width * 0.8f, before.center.y), Offset(width * 0.2f, before.center.y), 12, 16)
        Thread.sleep(100); rule.waitForIdle()
        val mid = bounds(busy.title)
        release(Offset(width * 0.2f, before.center.y))
        h.settle(2000)
        assertTrue("moved: $before -> $mid", abs(mid.left - before.left) < 1f)
        assertTrue("archived: ${h.archived()}", h.archived().isEmpty())
    }

    /** The chips on screen (the page keeps a copy of the list composed out of sight, of no size). */
    private fun chips(label: String) = rule.onAllNodesWithContentDescription(label, substring = true).fetchSemanticsNodes().filter { it.boundsInRoot.width > 0f }

    @Test fun chipArchives() {
        val h = home()
        assertEquals("one chip per archivable row", 2, chips("归档「").size)
        tap(chips("归档「${done.title}」").single().boundsInRoot.center)
        assertArchived(h, done.session)
    }

    // ── a chat ──

    private val talk = listOf(
        Fixtures.mine(1, "README 里的安装命令过时了，帮我改一下"),
        Fixtures.agent(2, "改好了：`pnpm i` 换成了 `pnpm install --frozen-lockfile`，已推到 main。").copy(ending = "all_done"),
        Fixtures.mine(3, "好的谢谢"),
        Fixtures.agent(4, "不客气，这件做完了。").copy(ending = "all_done"),
    )

    private fun chat(dark: Boolean = false): Harness {
        val h = Harness(rule)
        val of = ChatOf.Thread(Fixtures.THREAD)
        putChats(h, listOf(busy, done, alsoDone))
        h.fake.answer = { name, _ ->
            if (name == "chat.archive") putChats(h, listOf(busy, alsoDone))
            JsonNull
        }
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(talk, title = done.title).copy(archivable = true, key = done.session))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark)
        return h
    }

    @Test fun archiveExitLight() = archiveExit(false)
    @Test fun archiveExitDark() = archiveExit(true)

    private fun archiveExit(dark: Boolean) {
        val h = chat(dark)
        val of = ChatOf.Thread(Fixtures.THREAD)
        val r = h.record(if (dark) "archive-exit-dark" else "archive-exit-light")
        // The core's reply after sending: the same last post, but this chat has work again.
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(talk, title = done.title).copy(archivable = false, key = done.session))
        h.deliver()
        r.frames(5)
        assertEquals("exit retains the real button while it moves", 1, rule.onAllNodesWithText("归档这个 chat").fetchSemanticsNodes().size)
        rule.onNodeWithText("归档这个 chat").assertIsNotEnabled()
        assertTrue("leaving button cannot archive", h.fake.calls.none { it.first == "chat.archive" })
        r.frames(20)
        r.end()
        assertTrue("button removed after exit", rule.onAllNodesWithText("归档这个 chat").fetchSemanticsNodes().isEmpty())
    }

    @Test fun chatButtonArchives() {
        val h = chat()
        val buttons = rule.onAllNodesWithText("归档这个 chat").fetchSemanticsNodes()
        assertEquals("one button", 1, buttons.size)
        // Under the last all-done post, not the earlier one.
        assertTrue(buttons[0].boundsInRoot.top > bounds("这件做完了").top)
        tap(buttons[0].boundsInRoot.center)
        assertArchived(h, done.session)
        assertEquals("back to the chat list", listOf<Screen>(Screen.Home), h.app.stack)
    }

    @Test fun chatArchiveSlidesBackToList() {
        val h = chat()
        val r = h.record("archive-back")
        rule.onNodeWithText("归档这个 chat").performClick()
        r.frames(32)
        r.end()
        assertEquals("back to the chat list", listOf<Screen>(Screen.Home), h.app.stack)
    }

    @Test fun failedChatArchiveStaysInChat() {
        val h = chat()
        h.fake.answer = { name, _ ->
            if (name == "chat.archive") throw fail.still.core.CoreException("failed", "归档失败", null)
            JsonNull
        }
        val before = h.app.stack
        tap(bounds("归档这个 chat").center)
        h.settle()
        assertEquals("failed archive keeps the chat open", before, h.app.stack)
        assertTrue("failure is visible", h.app.toast?.contains("归档失败") == true)
    }

    // ── pictures ──

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun shots() {
        val h = home()
        shot("android-home")
        // Held mid-swipe: short of the threshold, then past it.
        val y = bounds(done.title).center.y
        val start = Offset(width * 0.85f, y)
        val short = Offset(width * 0.65f, y)
        val far = Offset(width * 0.4f, y)
        press(start)
        move(start, short, 10, 16)
        Thread.sleep(200); rule.waitForIdle()
        shot("android-swipe")
        move(short, far, 10, 16)
        Thread.sleep(300); rule.waitForIdle()
        shot("android-swipe-past")
        move(far, start, 12, 25)
        Thread.sleep(150)
        release(start)
        h.settle(2000)
        assertTrue("archived: ${h.archived()}", h.archived().isEmpty())
    }

    @Test fun shotsChat() {
        chat().settle()
        shot("android-chat")
    }
}
