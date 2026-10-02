// Decisions (screens/Decisions.kt) with real touches, injected as the system's own (UiAutomation, through the input
// dispatcher to the activity's window, in real time), on the app as it lays out its pages over a fake core:
// the decisions page swiped left sets the decision aside (decision.defer), right dismisses it (decision.dismiss); short
// of the threshold it springs back; up or down is not a swipe; a tap on an option answers (decision.answer), and a swipe
// begun on an option is still a swipe. In a chat, a tap on an option under the post answers; an answered one has no
// buttons, only its line. A text card: words typed in its field and sent (the button or the keyboard's send) reply
// (decision.reply); refused, the words stay; a swipe begun in the field is not a swipe, one begun elsewhere still is.
// A card of a type unknown here sends to its chat. `shots` pictures them (light and dark) into the app's files/shots.
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
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.DecisionItem
import fail.still.android.data.DecisionOption
import fail.still.android.data.DecisionsView
import fail.still.android.data.MessageCard
import fail.still.android.data.MessageDecision
import fail.still.android.data.RowAgent
import fail.still.android.data.RowDecision
import fail.still.android.data.RowMessage
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceMark
import fail.still.android.data.WorkspaceMarksView
import fail.still.android.screens.Pending
import fail.still.android.data.Attachment
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import fail.still.android.screens.Drafts
import fail.still.android.motion.Fixtures
import fail.still.android.motion.Harness
import fail.still.android.motion.MotionRule
import fail.still.core.CoreException
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DecisionsTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val change = DecisionOption("先只改设置页", "侧栏那行下次再说")
    private val both = DecisionOption("两处一起改", "多半个小时", recommended = true)
    private val asked = "间距那三处，前后对比在上面。设置页的行距从 12 改到 16、侧栏底部那行往上提 4px，要不要两处一起改？"

    private fun post(seq: Long, text: String, options: List<DecisionOption>, decision: MessageDecision = MessageDecision(resolved = false)): ChatMessage =
        Fixtures.agent(seq, text).copy(options = options, decision = decision)

    private val talk = listOf(
        Fixtures.mine(1, "侧栏底部那行和设置页的间距都不对"),
        Fixtures.agent(2, "看了：设置页每行之间是 12px，web 是 16px；侧栏底部那行比 web 低 4px。"),
    )
    private val gap = post(3, asked, listOf(change, both))

    private val archive = post(9, "归档页的时间要不要往右挪到行尾？", listOf(DecisionOption("挪到行尾"), DecisionOption("先不动", recommended = true)))
    private fun item(m: ChatMessage, before: List<ChatMessage>, title: String, session: String) = DecisionItem(
        station = Fixtures.STATION, stationName = "studio", session = session, thread = m.thread, title = title, seq = m.seq,
        message = m, before = before, options = m.options!!, text = "奏 · ${m.text.take(20)}",
    )
    private val first = item(gap, talk, "侧栏和设置的几处间距", "ember:c-1")

    private val keyAsked = "Stripe 的测试 key 还没配，发我一个 sk_test_ 开头的 key，我配到 dev 环境里跑一遍支付流程。"
    private val keyPost = Fixtures.agent(12, keyAsked).copy(card = MessageCard(type = "text", placeholder = "sk_test_…"), decision = MessageDecision(resolved = false))
    private val keyItem = DecisionItem(
        station = Fixtures.STATION, stationName = "studio", session = "ember:c-7", thread = keyPost.thread, title = "支付流程接 Stripe", seq = keyPost.seq,
        message = keyPost, before = listOf(Fixtures.mine(11, "支付那块先在 dev 上跑通")), options = emptyList(), card = keyPost.card, text = "奏 · Stripe 的测试 key 还没配",
    )
    private val second = item(archive, listOf(Fixtures.mine(8, "归档页时间那块看着挤")), "归档页时间", "ember:c-2")

    // ── driving ──

    private fun freshDrafts(h: Harness) {
        rule.runOnUiThread {
            listOf(first, second, keyItem).forEach { item ->
                Drafts.of(rule.activity, h.fake.core, "decision:${item.station}:${item.thread}:${item.seq}").apply {
                    take(); starting = false; save()
                }
            }
        }
    }

    private fun page(dark: Boolean = false): Harness {
        val h = Harness(rule)
        freshDrafts(h)
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(listOf(first, second), 2u, loading = false))
        h.launch(listOf(Screen.Home, Screen.Decisions), dark)
        return h
    }

    private val width get() = rule.onRoot().fetchSemanticsNode().size.width.toFloat()
    private fun bounds(text: String, substring: Boolean = true): Rect = rule.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().first().boundsInRoot
    /** An option's button (its label alone: the post's words may hold it too). */
    private fun option(o: DecisionOption): Rect = bounds(o.label, substring = false)
    /** The post's words on the page: where it is. */
    private fun postAt(): Rect = bounds("间距那三处")

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
        // The Compose clock can settle before the system finishes focusing the test window.
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(350)
        // A pointer left down by a gesture cut short would have every DOWN after it refused.
        send(MotionEvent.ACTION_CANCEL, p); Thread.sleep(50)
        downAt = SystemClock.uptimeMillis()
        check(send(MotionEvent.ACTION_DOWN, p)) { "DOWN not injected" }
    }

    private fun move(from: Offset, to: Offset, steps: Int, stepMs: Long) {
        for (k in 1..steps) { Thread.sleep(stepMs); check(send(MotionEvent.ACTION_MOVE, from + (to - from) * (k.toFloat() / steps))) { "MOVE not injected" } }
    }

    private fun release(p: Offset) { Thread.sleep(16); check(send(MotionEvent.ACTION_UP, p)) { "UP not injected" }; Thread.sleep(50); rule.waitForIdle() }

    /** A finger from `start` to `end` in `steps` moves, `stepMs` apart. */
    private fun drag(start: Offset, end: Offset, steps: Int = 12, stepMs: Long = 16) {
        press(start)
        try { move(start, end, steps, stepMs) } finally { release(end) }
    }

    private fun tap(p: Offset) = drag(p, p, 1, 40)

    private fun Harness.acted() = fake.calls.filter { it.first.startsWith("decision.") }

    private fun assertOneCall(h: Harness, name: String, m: ChatMessage) {
        h.settle()
        val acted = h.acted()
        assertEquals("calls: $acted", 1, acted.size)
        assertEquals(name, acted[0].first)
        assertEquals(m.seq, acted[0].second["seq"]!!.jsonPrimitive.long)
        assertEquals(m.thread, acted[0].second["thread"]!!.jsonPrimitive.long)
        assertEquals(Fixtures.STATION, acted[0].second["station"]!!.jsonPrimitive.content)
    }

    private fun assertInPlace(before: Rect) {
        val after = postAt()
        assertTrue("not back in place: $before -> $after", abs(after.left - before.left) < 1f && abs(after.top - before.top) < 1f)
    }

    // ── the decisions page ──

    @Test fun emptyQueueReturnsToPreviousPage() {
        val h = page()
        val recording = h.record("decisions-empty-back")
        recording.frames(30)
        recording.frame { h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, loading = false)) }
        recording.frames(40)
        recording.end()
        rule.runOnIdle { assertEquals(listOf(Screen.Home), h.app.stack) }
    }

    @Test fun loadingEmptyQueueStaysUntilLoaded() {
        val h = Harness(rule)
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, loading = true))
        h.launch(listOf(Screen.Home, Screen.Settings, Screen.Decisions))
        rule.runOnIdle { assertEquals(Screen.Decisions, h.app.stack.last()) }
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, loading = false))
        h.settle()
        rule.runOnIdle { assertEquals(listOf(Screen.Home, Screen.Settings), h.app.stack) }
    }

    @Test fun emptyQueueDoesNotPopPageAboveIt() {
        val h = page()
        rule.runOnUiThread { h.app.push(Screen.Appearance) }
        h.settle()
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, loading = false))
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Appearance, h.app.stack.last()) }
        rule.runOnUiThread { h.app.pop() }
        h.settle()
        rule.runOnIdle { assertEquals(listOf(Screen.Home), h.app.stack) }
    }

    @Test fun swipeLeftSetsItAside() {
        val h = page()
        val y = postAt().center.y
        drag(Offset(width * 0.8f, y), Offset(width * 0.1f, y))
        assertOneCall(h, "decision.defer", gap)
        // The next one is in front; the one set aside is last (2 / 2 → it is still there, behind).
        rule.onNodeWithText(second.title).assertExists()
        rule.onNodeWithText("1 / 2").assertExists()
    }

    @Test fun swipeRightDismissesIt() {
        val h = page()
        val y = postAt().center.y
        drag(Offset(width * 0.2f, y), Offset(width * 0.9f, y))
        assertOneCall(h, "decision.dismiss", gap)
        rule.onNodeWithText(second.title).assertExists()
        rule.onNodeWithText("1 / 1").assertExists()
    }

    @Test fun shortSlowSwipeSpringsBack() {
        val h = page()
        val before = postAt()
        drag(Offset(width * 0.4f, before.center.y), Offset(width * 0.52f, before.center.y), steps = 20, stepMs = 25)
        h.settle(2000)
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
        assertInPlace(before)
    }

    @Test fun verticalSwipeIsNotASwipe() {
        val h = page()
        val before = postAt()
        drag(Offset(width * 0.5f, before.center.y), Offset(width * 0.56f, before.center.y - 300f))
        h.settle(2000)
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
        // Not moved across (it may have scrolled up or down).
        assertTrue("moved across: ${postAt()}", abs(postAt().left - before.left) < 1f)
        rule.onNodeWithText(first.title).assertExists()
    }

    @Test fun tapOnAnOptionAnswers() {
        val h = page()
        tap(option(both).center)
        assertOneCall(h, "decision.answer", gap)
        assertEquals(both.label, h.acted()[0].second["option"]!!.jsonPrimitive.content)
        rule.onNodeWithText(second.title).assertExists()
    }

    @Test fun swipeBegunOnAnOptionIsASwipe() {
        val h = page()
        val o = option(change)
        drag(Offset(width * 0.2f, o.center.y), Offset(width * 0.9f, o.center.y))
        assertOneCall(h, "decision.dismiss", gap)
    }

    @Test fun initiallyEmptyPageReturns() {
        val h = Harness(rule)
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, loading = false))
        h.launch(listOf(Screen.Home, Screen.Decisions))
        rule.runOnIdle { assertEquals(listOf(Screen.Home), h.app.stack) }
    }

    // ── a text card ──

    private fun textPage(dark: Boolean = false, card: MessageCard = keyPost.card!!): Harness {
        // As the app's activity (MainActivity, the manifest): edge to edge, resized for the keyboard, not panned.
        val h = Harness(rule)
        freshDrafts(h)
        val it = keyItem.copy(card = card, message = keyPost.copy(card = card))
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(listOf(it, first), 2u, loading = false))
        h.launch(listOf(Screen.Home, Screen.Decisions), dark)
        rule.runOnUiThread {
            @Suppress("DEPRECATION") rule.activity.window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            android.util.Log.i("DecisionsTest", "softInputMode=" + rule.activity.window.attributes.softInputMode)
        }
        return h
    }
    private fun field(): Rect = rule.onNode(hasSetTextAction()).fetchSemanticsNode().boundsInRoot
    private fun sendButton(): Rect = rule.onAllNodes(androidx.compose.ui.test.hasContentDescription("发送")).fetchSemanticsNodes().first().boundsInRoot
    private fun keyAt(): Rect = bounds("Stripe 的测试 key")

    private fun typeIn(text: String) {
        tap(field().center)
        rule.onNode(hasSetTextAction()).performTextInput(text)
        // The keyboard up and the page laid out above it.
        Thread.sleep(1200); rule.waitForIdle()
        origin = null
    }

    @Test fun textCardShowsItsPlaceholder() {
        textPage()
        rule.onNodeWithText("sk_test_…").assertExists()
        rule.onNodeWithText("← 待定　不再提醒 →").assertExists()
    }

    @Test fun textCardSendReplies() {
        val h = textPage()
        typeIn("sk_test_51Hx")
        tap(sendButton().center)
        assertOneCall(h, "decision.reply", keyPost)
        assertEquals("sk_test_51Hx", h.acted()[0].second["text"]!!.jsonPrimitive.content)
        // Replied: the next one is in front.
        rule.onNodeWithText(first.title).assertExists()
    }

    @Test fun textCardMultilineReply() {
        val h = textPage()
        typeIn("第一行\n第二行")
        assertTrue(h.acted().isEmpty())
        tap(sendButton().center)
        assertOneCall(h, "decision.reply", keyPost)
        assertEquals("第一行\n第二行", h.acted()[0].second["text"]!!.jsonPrimitive.content)
    }

    @Test fun optionsCardFreeformReply() {
        val h = page()
        rule.onNodeWithText(both.label).assertExists()
        typeIn("先调间距\n颜色不动")
        tap(sendButton().center)
        assertOneCall(h, "decision.reply", gap)
        assertEquals("先调间距\n颜色不动", h.acted()[0].second["text"]!!.jsonPrimitive.content)
        rule.onNodeWithText(second.title).assertExists()
    }

    @Test fun sharedComposerSendsAttachmentsAndQuotes() {
        val h = page()
        rule.runOnUiThread {
            val draft = Drafts.of(rule.activity, h.fake.core, "decision:${first.station}:${first.thread}:${first.seq}")
            draft.files.add(Pending(991L, "notes.txt", 12L, null).apply { done = Attachment("notes.txt", "uploads/notes.txt", 12L) })
            draft.quote("林晓", "看这一处", "t1", "person")
        }
        h.settle()
        rule.onNodeWithText("notes.txt").assertExists()
        tap(sendButton().center)
        assertOneCall(h, "decision.reply", gap)
        val params = h.acted()[0].second
        assertEquals("", params["text"]!!.jsonPrimitive.content)
        assertEquals("uploads/notes.txt", params["attachments"]!!.jsonArray.single().jsonObject["path"]!!.jsonPrimitive.content)
        assertEquals("看这一处", params["quotes"]!!.jsonArray.single().jsonObject["text"]!!.jsonPrimitive.content)
    }

    @Test fun textCardEmptySendsNothing() {
        val h = textPage()
        tap(sendButton().center)
        h.settle()
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
    }

    @Test fun textCardRefusedKeepsTheWords() {
        val h = textPage()
        h.fake.answer = { name, _ -> if (name == "decision.reply") throw CoreException("station_offline", "station 不在线", null) else kotlinx.serialization.json.JsonNull }
        typeIn("sk_test_kept")
        tap(sendButton().center)
        h.settle()
        assertEquals(listOf("decision.reply"), h.acted().map { it.first })
        rule.onNodeWithText("sk_test_kept").assertExists()
        rule.onNodeWithText(keyItem.title).assertExists()
        rule.onNodeWithText("没能回复", substring = true).assertExists()
    }

    @Test fun swipeBegunInTheFieldIsNotASwipe() {
        val h = textPage()
        val f = field()
        val before = keyAt()
        drag(Offset(f.left + 8f, f.center.y), Offset(width * 0.95f, f.center.y))
        drag(Offset(f.right - 8f, f.center.y), Offset(width * 0.05f, f.center.y))
        h.settle(2000)
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
        assertTrue("moved: $before -> ${keyAt()}", abs(keyAt().left - before.left) < 1f)
        rule.onNodeWithText(keyItem.title).assertExists()
    }

    @Test fun swipeElsewhereOnATextCardSetsItAside() {
        val h = textPage()
        val y = keyAt().center.y
        drag(Offset(width * 0.8f, y), Offset(width * 0.1f, y))
        assertOneCall(h, "decision.defer", keyPost)
    }

    @Test fun swipeElsewhereOnATextCardDismissesIt() {
        val h = textPage()
        typeIn("半截")
        // The keyboard up, the messages shorter: just above the field, on what the card shows.
        val y = field().top - 120f
        drag(Offset(width * 0.2f, y), Offset(width * 0.9f, y))
        assertOneCall(h, "decision.dismiss", keyPost)
    }

    @Test fun unknownCardGoesToItsChat() {
        val h = textPage(card = MessageCard(type = "date"))
        rule.onNodeWithText("去 chat 里回").assertExists()
        tap(bounds("去 chat 里回").center)
        h.settle()
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
        assertTrue(h.fake.calls.toString(), rule.onAllNodesWithText("去 chat 里回").fetchSemanticsNodes().isEmpty())
    }

    // ── in a chat ──

    private val resolved = post(
        2, "设置页的标题要不要加粗？", listOf(DecisionOption("加粗"), DecisionOption("先不改", recommended = true)),
        MessageDecision(resolved = true, answeredBy = "林晓", chosen = "先不改", text = "林晓 选了「先不改」"),
    )
    private val chatTalk = listOf(Fixtures.mine(1, "设置页再看一下"), resolved, Fixtures.mine(3, "先不改"), Fixtures.agent(4, "好，标题不动。"), gap.copy(seq = 5, ts = "t5"))

    private fun chat(dark: Boolean = false): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(chatTalk, title = "侧栏和设置的几处间距"))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))), dark)
        return h
    }

    @Test fun inChatTapOnAnOptionAnswers() {
        val h = chat()
        tap(option(change).center)
        assertOneCall(h, "decision.answer", gap.copy(seq = 5))
        assertEquals(change.label, h.acted()[0].second["option"]!!.jsonPrimitive.content)
    }

    @Test fun inChatTextCardHasNothingUnder() {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(listOf(Fixtures.mine(1, "支付那块先在 dev 上跑通"), keyPost.copy(seq = 2, ts = "t2")), title = "支付流程接 Stripe"))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        rule.onNodeWithText("Stripe 的测试 key", substring = true).assertExists()
        rule.onNodeWithText("sk_test_…").assertDoesNotExist()
        rule.onNodeWithText("去 chat 里回").assertDoesNotExist()
    }

    @Test fun inChatAnsweredHasItsLineNoButtons() {
        chat()
        rule.onNodeWithText("林晓 选了「先不改」").assertExists()
        rule.onNodeWithText("加粗").assertDoesNotExist()
    }

    private fun answerMotion(dark: Boolean) {
        val h = chat(dark)
        val p = option(both).center
        val rec = h.record("decision-answer-${if (dark) "dark" else "light"}")
        press(p)
        rec.frames(18)
        send(MotionEvent.ACTION_UP, p)
        rec.frames(8)
        h.deliver()
        assertEquals("one answer", 1, h.acted().size)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(
            chatTalk.map { if (it.seq == 5L) it.copy(decision = MessageDecision(resolved = true, text = "左子健 选了「两处一起改」")) else it },
            title = "侧栏和设置的几处间距",
        ))
        h.deliver()
        rec.frames(60)
        rec.end()
        rule.onNodeWithText(both.label, substring = false).assertDoesNotExist()
        rule.onNodeWithText("左子健 选了「两处一起改」").assertExists()
    }

    @Test fun answerMotionLight() { answerMotion(false) }
    @Test fun answerMotionDark() { answerMotion(true) }

    // ── pictures ──

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun row(id: String, title: String, last: String, stateText: String? = null, tone: String? = null, settled: Boolean = false, decision: RowDecision? = null) = ChatItem(
        id = id, session = id, thread = null, title = title,
        agents = listOf(RowAgent(key = id, runtime = "claude", process = "idle", pending = 0, agentText = "Claude", maker = Fixtures.anthropic, statusText = "空闲")),
        last = RowMessage(seq = 1, authorKind = "agent", author = id, text = last, createdAt = Fixtures.NOW, preview = last),
        unread = false, mine = true, lastActiveAt = Fixtures.NOW, station = Fixtures.STATION, stationName = "studio",
        decision = decision, settled = if (settled) true else null, archivable = if (settled) true else null, stateText = stateText, tone = tone,
    )

    private fun home(dark: Boolean) {
        val h = Harness(rule)
        val items = listOf(
            row("ember:c-1", "侧栏和设置的几处间距", "改好了", stateText = "奏 · 间距那三处，前后对比在上面", tone = "wait", decision = RowDecision(3, listOf(change, both), text = "奏 · 间距那三处，前后对比在上面")),
            row("ember:c-3", "登录页 Safari 点不动", "表单提交前被吞掉了", stateText = "在等：CI 跑完"),
            row("ember:c-4", "归档页时间", "挪到行尾了", stateText = "奏 · 归档页的时间要不要往右挪", tone = "wait"),
            row("ember:c-5", "README 里的命令", "改好了，已推到 main", stateText = "做完了", settled = true),
            row("ember:c-6", "换掉旧的图标", "都换好了", stateText = "做完了", settled = true),
        )
        val chats = ChatsView(
            me = fail.still.android.data.Me(id = Fixtures.account.email), stations = listOf(StationState(Fixtures.STATION, "st", "studio", "online")),
            loading = false, days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", items)),
        )
        h.fake.put(Topics.chats(Fixtures.WS, false), chats)
        h.fake.put(Topics.chats(Fixtures.WS, true), chats)
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats.copy(days = emptyList()))
        h.fake.put(Topics.workspaceMarks(Fixtures.WS), WorkspaceMarksView(mapOf(Fixtures.WS to WorkspaceMark(alert = 0u, unread = 0u, wait = 2u, decisions = 2u))))
        h.launch(listOf(Screen.Home), dark)
        shot("home-${if (dark) "dark" else "light"}")
    }

    private fun pictures(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        chat(dark).settle()
        shot("chat-$theme")
    }

    private fun pagePictures(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        val h = page(dark)
        shot("decisions-$theme")
        // Held mid-swipe, each way: what letting it go there does shows under it.
        val y = postAt().center.y
        for ((name, way) in listOf("left" to -1, "right" to 1)) {
            val start = Offset(width * 0.5f, y)
            val mid = Offset(start.x + way * width * 0.28f, y)
            press(start)
            move(start, mid, 10, 16)
            Thread.sleep(200); rule.waitForIdle()
            shot("decisions-swipe-$name-$theme")
            // Back where it started and let go: it stays.
            move(mid, start, 10, 25)
            Thread.sleep(150)
            release(start)
            h.settle(2000)
        }
        assertTrue("acted: ${h.acted()}", h.acted().isEmpty())
    }

    private fun textPictures(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        textPage(dark).settle()
        shot("decisions-text-$theme")
        typeIn("sk_test_51HxQ2eLkd")
        Thread.sleep(600); rule.waitForIdle()
        shot("decisions-text-typing-$theme")
        // With the keyboard, as the screen shows it.
        val screen = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "decisions-text-typing-screen-$theme.png")).use { screen.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun shotsText() { textPictures(false) }

    @Test fun shots() {
        pictures(false)
    }
    @Test fun shotsDark() { pictures(true) }
    @Test fun shotsPage() { pagePictures(false) }
    @Test fun shotsPageDark() { pagePictures(true) }
    @Test fun shotsHome() { home(false) }
    @Test fun shotsHomeDark() { home(true) }
}
