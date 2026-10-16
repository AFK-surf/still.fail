package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.Session
import fail.still.android.data.Disk
import fail.still.android.data.Host
import fail.still.android.data.Memory
import fail.still.android.data.Meter
import fail.still.android.data.HostDetail
import fail.still.android.data.NetFigure
import fail.still.android.data.StationNet
import fail.still.android.data.Topics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.io.FileOutputStream

/**
 * A chat's bar names the station it runs on: on its first agent's tile (the station's icon, or its name where it has
 * none), one tap opening the agent's card whose station row opens the station's; or as a tag of its own while the chat
 * has no agent, a tap opening the station's card; how it is reached a dot on the tile's corner. `shots` pictures them
 * (light and dark, directly, through a relay, away) into files/shots.
 */
class StationChipTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val host = Host(
        hostname = "studio", os = "macOS", arch = "arm64", cpus = 16, cpuModel = "Apple M4 Max", load = 0.2, uptimeSec = 1e5,
        memory = Memory(64L shl 30, 20L shl 30), disk = Disk("/", 2000L shl 30, 700L shl 30), emberRssBytes = 1, checkedAt = 1,
        summary = "16 核 · 64 GB", line = "macOS 26.6 · 16 核 · 64 GB · 已开机 1 天", facts = emptyList(), usage = "内存 20 / 64 GB · 磁盘 700 GB / 2 TB", emberText = "still.fail 38 MB",
        meters = listOf(Meter(label = "CPU", short = "CPU", percent = 19, left = 81, level = "ok", value = "19%", remaining = "空闲 81%", big = "81", unit = "%", title = "CPU 空闲", total = "负载 3.0"), Meter(label = "内存", short = "内存", percent = 69, left = 31, level = "ok", value = "69%", remaining = "剩 44.0 G", big = "20", unit = "GB", title = "内存剩", total = "共 64 GB"), Meter(label = "磁盘", short = "磁盘", percent = 85, left = 15, level = "amber", value = "85%", remaining = "剩 300.0 G", big = "300", unit = "GB", title = "磁盘剩", total = "共 2000 GB")),
        identity = "Apple M4 Max · 64 GB · macOS 26.6", details = listOf(HostDetail("主机名", "studio"), HostDetail("芯片", "Apple M4 Max · 16 核 · arm64"), HostDetail("已运行", "1 天 3 小时"), HostDetail("still.fail", "进程占用 38 MB")),
    )
    private val net = StationNet(path = "直连", via = "direct", rtt = NetFigure("12 ms", "ok"), rttHistory = emptyList(), down = "1.2 MB/s", up = "30 KB/s", total = "", downTotal = "212 MB", upTotal = "9.6 MB")
    private val studio = Fixtures.station.copy(name = "Studio", emoji = "🍎", summary = "1 个 agent 在跑 · Apple M4 Max · 64 GB · macOS 26.6", host = host, net = net)
    private val mini = Fixtures.station.copy(station = "${Fixtures.WS}/mini", id = "mini", name = "Mac mini", emoji = "🐧")

    private val talk = listOf(Fixtures.mine(1, "README 里的安装命令过时了，帮我改一下"), Fixtures.agent(2, "改好了，已推到 main。").copy(ending = "all_done"))

    private val agent = ChatAgent(
        session = Session(
            key = "ember:c-1", runtime = "claude", process = "running", pending = 0, statusText = "进行中", tone = "accent", mark = "run",
            titleText = "修一下登录", agentText = "Claude", maker = Fixtures.anthropic, runtimeText = "Claude Code", efforts = listOf("high"),
        ),
        status = "running", badge = "run", profiles = emptyList(), choices = emptyList(), attention = emptyList(), turns = emptyList(), threads = emptyList(), jobs = emptyList(),
    )

    private fun open(stations: List<fail.still.android.data.StationView>, dark: Boolean = false, agents: Boolean = true): Harness {
        val h = Harness(rule)
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(talk).let { if (agents) it.copy(agents = listOf(agent)) else it })
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark)
        // After launching, which puts the one station of the fixtures.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), stations) }
        h.settle()
        return h
    }

    private val tile = "Claude · Studio"

    @Test fun theAgentsTileCarriesIt() {
        open(listOf(studio))
        assertEquals(1, rule.onAllNodesWithContentDescription(tile).fetchSemanticsNodes().size)
        // Its icon only: the name is not written out beside it.
        assertTrue(rule.onAllNodesWithText("Studio").fetchSemanticsNodes().isEmpty())
    }

    @Test fun withoutAnIconItsName() {
        open(listOf(studio.copy(emoji = null, icon = null)))
        rule.onNodeWithText("Studio").assertExists()
    }

    @Test fun noAgentATagOfItsOwn() {
        val h = open(listOf(studio), agents = false)
        rule.onNodeWithContentDescription("Studio").performClick()
        h.settle()
        rule.onNodeWithText("1 个 agent 在跑 · Apple M4 Max · 64 GB · macOS 26.6").assertExists()
    }

    @Test fun tapOpensTheCard() {
        val h = open(listOf(studio, mini))
        rule.onNodeWithContentDescription(tile).performClick()
        h.settle()
        rule.onNodeWithText("Station").assertExists()
        rule.onNodeWithText("Studio").performClick()
        h.settle()
        rule.onNodeWithText("1 个 agent 在跑 · Apple M4 Max · 64 GB · macOS 26.6").assertExists()
        rule.onNodeWithText("机器详情").performClick()
        h.settle()
        assertEquals(Screen.Station(Fixtures.STATION), h.app.stack.last())
    }

    @Test fun shotsLight() = shots(false)
    @Test fun shotsDark() = shots(true)

    private fun shots(dark: Boolean) {
        val h = open(listOf(studio, mini), dark)
        val tag = if (dark) "dark" else "light"
        shot("station-tile-$tag")
        // How it is reached, a dot on the tile's corner: through a relay, away.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(studio.copy(net = net.copy(path = "北京中继", via = "relay")), mini)) }
        h.settle()
        shot("station-tile-relay-$tag")
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(studio.copy(online = false), mini)) }
        h.settle()
        shot("station-tile-offline-$tag")
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(studio, mini)) }
        h.settle()
        rule.onNodeWithContentDescription(tile).performClick()
        h.settle()
        shot("agent-card-$tag")
        rule.onNodeWithText("Studio").performClick()
        h.settle()
        shot("station-peek-$tag")
        rule.runOnUiThread { h.app.sheet = null; h.fake.put(Topics.stations(Fixtures.WS), listOf(studio.copy(emoji = null, icon = null), mini)) }
        h.settle()
        shot("station-tile-name-$tag")
        rule.runOnUiThread { h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(talk)) }
        h.settle()
        shot("station-chip-name-$tag")
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
