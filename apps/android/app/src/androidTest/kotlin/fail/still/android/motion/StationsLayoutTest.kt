package fail.still.android.motion

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import fail.still.android.Screen
import fail.still.android.data.Disk
import fail.still.android.data.Host
import fail.still.android.data.Link
import fail.still.android.data.Memory
import fail.still.android.data.Meter
import fail.still.android.data.NetFigure
import fail.still.android.data.StationNet
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** The stations' list keeps every station where it is, as tall, whatever state each is in. */
class StationsLayoutTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val host = Host(
        hostname = "h", os = "macOS", arch = "arm64", cpus = 10, cpuModel = "Apple M2", load = 0.2, uptimeSec = 1e5,
        memory = Memory(32L shl 30, 12L shl 30), disk = Disk("/", 500L shl 30, 200L shl 30), emberRssBytes = 1, checkedAt = 1,
        summary = "", line = "", facts = emptyList(), emberText = "",
        meters = listOf(Meter("CPU", "C", 20, "ok", "20%"), Meter("内存", "M", 40, "ok", "40%"), Meter("磁盘", "D", 60, "ok", "60%")),
    )
    private val net = StationNet(path = "直连", rtt = NetFigure("12 ms", "ok"), rttHistory = emptyList(), down = "1.2 MB/s", up = "30 KB/s", total = "", downTotal = "212 MB", upTotal = "9.6 MB")

    private fun station(name: String, online: Boolean, read: Boolean = true) = StationView(
        station = "${Fixtures.WS}/$name", id = name, name = name, summary = if (online) "10 核 · 32 GB" else "3 小时前离线",
        face = if (online) "idle" else "offline", online = online, link = Link(if (online) "online" else "offline"),
        runtimes = emptyList(), models = emptyList(), host = if (online && read) host else null, net = if (online && read) net else null,
    )

    @Test fun states() {
        val h = Harness(rule)
        h.launch(listOf(Screen.Stations))
        val shown = listOf(
            "online" to listOf(station("studio", true), station("mini", true), station("air", true)),
            "mixed" to listOf(station("studio", false), station("mini", true, read = false), station("air", true)),
            "offline" to listOf(station("studio", true), station("mini", false), station("air", false)),
        )
        val tops = shown.map { (name, list) ->
            rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), list) }
            h.settle()
            h.record(name).end()
            list.map { rule.onNodeWithText(it.name).getBoundsInRoot().top }.also { Log.i("motion", "$name: $it") }
        }
        tops.drop(1).forEach { assertEquals(tops[0], it) }
    }


    /** How it looks: a station online, one offline, one not read yet. */
    @Test fun looksLight() = looks(false)
    @Test fun looksDark() = looks(true)

    private fun looks(dark: Boolean) {
        val h = Harness(rule)
        h.launch(listOf(Screen.Stations), dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station("studio", true), station("mini", false), station("air", true, read = false))) }
        h.settle()
        h.record("look-${if (dark) "dark" else "light"}").end()
    }
}
