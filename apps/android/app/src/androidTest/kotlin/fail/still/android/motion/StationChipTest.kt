package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Disk
import fail.still.android.data.Host
import fail.still.android.data.Memory
import fail.still.android.data.Meter
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
 * A chat's bar names the station it runs on once its workspace has more than one (its icon and name), and a tap on it
 * opens the station's card; with one station it says nothing. `shots` pictures them (light and dark) into files/shots.
 */
class StationChipTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val host = Host(
        hostname = "studio", os = "macOS", arch = "arm64", cpus = 16, cpuModel = "Apple M4 Max", load = 0.2, uptimeSec = 1e5,
        memory = Memory(64L shl 30, 20L shl 30), disk = Disk("/", 2000L shl 30, 700L shl 30), emberRssBytes = 1, checkedAt = 1,
        summary = "16 核 · 64 GB", line = "macOS 26.6 · 16 核 · 64 GB · 已开机 1 天", facts = emptyList(), usage = "内存 20 / 64 GB · 磁盘 700 GB / 2 TB", emberText = "still.fail 38 MB",
        meters = listOf(Meter("CPU", "C", 19, "ok", "19%"), Meter("内存", "M", 43, "ok", "43%"), Meter("磁盘", "D", 38, "ok", "38%")),
    )
    private val net = StationNet(path = "直连", rtt = NetFigure("12 ms", "ok"), rttHistory = emptyList(), down = "1.2 MB/s", up = "30 KB/s", total = "", downTotal = "212 MB", upTotal = "9.6 MB")
    private val studio = Fixtures.station.copy(name = "Studio", emoji = "🍎", summary = "1 个 agent 在跑", host = host, net = net)
    private val mini = Fixtures.station.copy(station = "${Fixtures.WS}/mini", id = "mini", name = "Mac mini", emoji = "🐧")

    private val talk = listOf(Fixtures.mine(1, "README 里的安装命令过时了，帮我改一下"), Fixtures.agent(2, "改好了，已推到 main。").copy(ending = "all_done"))

    private fun open(stations: List<fail.still.android.data.StationView>, dark: Boolean = false): Harness {
        val h = Harness(rule)
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(talk))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark)
        // After launching, which puts the one station of the fixtures.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), stations) }
        h.settle()
        return h
    }

    @Test fun oneStationSaysNothing() {
        open(listOf(studio))
        assertTrue(rule.onAllNodesWithContentDescription("Studio").fetchSemanticsNodes().isEmpty())
    }

    @Test fun tapOpensTheCard() {
        val h = open(listOf(studio, mini))
        rule.onNodeWithContentDescription("Studio").performClick()
        h.settle()
        rule.onNodeWithText("1 个 agent 在跑").assertExists()
        rule.onNodeWithText("机器详情").performClick()
        h.settle()
        assertEquals(Screen.Station(Fixtures.STATION), h.app.stack.last())
    }

    @Test fun shotsLight() = shots(false)
    @Test fun shotsDark() = shots(true)

    private fun shots(dark: Boolean) {
        val h = open(listOf(studio, mini), dark)
        val tag = if (dark) "dark" else "light"
        shot("station-chip-$tag")
        rule.onNodeWithContentDescription("Studio").performClick()
        h.settle()
        shot("station-peek-$tag")
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
