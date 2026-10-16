// A station's drive (drive/*.kt) on the fake core: its row on the station's page, the roots, a folder of every kind,
// what a held row offers, nothing lent (for an owner and for a member), the folder picker, the reader (its bars, its
// contents, search, a paper) and the player (a small video and its subtitle served through `drive.read`). Each is
// pictured light and dark (settled.png under motion/drive-*). A file opened again is read from the phone (DriveCache).
package fail.still.android.motion

import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.filter
import androidx.compose.ui.test.onFirst
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.Counts
import fail.still.android.data.DriveEntry
import fail.still.android.data.DriveFolder
import fail.still.android.data.DrivePlace
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Overview
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import fail.still.android.data.WorkspaceView
import fail.still.android.drive.DriveCache
import fail.still.android.drive.DriveUpload
import fail.still.android.drive.DriveUploads
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DriveTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val books = "/Users/alice/书"
    private val films = "/Volumes/media/影视"

    private fun station(roots: List<DriveRoot>) = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "", drive = DriveRoots(roots),
        ),
    )

    private val roots = listOf(
        DriveRoot(books, "书", "ok"),
        DriveRoot(films, "影视", "ok"),
        DriveRoot("/Users/alice/Documents", "Documents", "unreadable"),
    )

    private fun entry(name: String, kind: String, size: Long = 0, sizeText: String = "", time: String = "9/27") =
        DriveEntry(name, kind == "folder", size, Fixtures.NOW, if (kind == "folder") "" else "x", kind, sizeText, time)

    private val folder = DriveFolder(
        path = "", folders = 2, files = 9, countText = "2 个文件夹 · 9 个文件",
        entries = listOf(
            entry("三体", "folder", time = "14:05"),
            entry("杂记", "folder", time = "2024/3/2"),
            entry("三体.txt", "text", 2_400_000, "2.3 MB"),
            entry("笔记.md", "markdown", 12_000, "12 KB", "14:05"),
            entry("E01.mp4", "video", 36_000_000, "34.3 MB"),
            entry("E01.srt", "subtitle", 40_000, "39 KB"),
            entry("海报.jpg", "image", 820_000, "801 KB"),
            entry("说明.pdf", "pdf", 1_200_000, "1.1 MB"),
            entry("main.py", "code", 3_000, "2.9 KB"),
            entry("数据.csv", "csv", 9_000, "8.8 KB"),
            entry("安装包.zip", "other", 50_000_000, "47.7 MB", "2023/8/1"),
        ),
    )

    private fun launch(stack: List<Screen>, dark: Boolean, role: String = "owner", roots: List<DriveRoot> = this.roots, folder: DriveFolder = this.folder): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = role))
        h.fake.put(Topics.stations(Fixtures.WS), listOf(station(roots)))
        h.fake.put(Topics.drive(st, books, ""), folder)
        h.fake.set(Topics.drivePlace(st, books, "三体.txt"), kotlinx.serialization.json.Json.encodeToJsonElement(DrivePlace.serializer(), DrivePlace(at = 3_300.0, of = 8_000.0, changed = Fixtures.NOW)))
        h.fake.answer = answer
        h.launch(stack, dark)
        // Harness.launch puts the station without its drive: the station with it again, once the app is up.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station(roots))) }
        h.settle()
        return h
    }

    /** The files `drive.read` serves: a novel, a video and its subtitle. */
    private val files: Map<String, ByteArray> by lazy {
        val assets = InstrumentationRegistry.getInstrumentation().context.assets
        mapOf(
            "三体.txt" to novel().toByteArray(Charsets.UTF_8),
            "E01.mp4" to assets.open("drive-sample.mp4").use { it.readBytes() },
            "E01.srt" to "1\n00:00:00,000 --> 00:00:30,000\n第一集：山顶上的灯\n".toByteArray(),
        )
    }

    private val answer: (String, kotlinx.serialization.json.JsonObject) -> kotlinx.serialization.json.JsonElement = { name, p ->
        when (name) {
            "drive.read" -> {
                val bytes = files[p["path"]!!.jsonPrimitive.content] ?: ByteArray(0)
                val at = p["offset"]!!.jsonPrimitive.long.toInt().coerceAtMost(bytes.size)
                val n = p["length"]!!.jsonPrimitive.long.toInt().coerceAtMost(bytes.size - at)
                buildJsonObject {
                    put("type", "application/octet-stream"); put("total", bytes.size); put("mtime", Fixtures.NOW)
                    put("bytes", Base64.encodeToString(bytes.copyOfRange(at, at + n), Base64.NO_WRAP))
                }
            }
            "drive.folders" -> folders(p["path"]?.jsonPrimitive?.content)
            else -> JsonNull
        }
    }

    /**
     * The station's folders as a Mac's home shows them to the picker: a heap of them at the home (the ones macOS keeps
     * from a station without full disk access unreadable), the usual places and two disks, two levels of a project
     * under it; Documents refused as the station refuses it.
     */
    private fun folders(asked: String?): kotlinx.serialization.json.JsonElement {
        val home = "/Users/alice"
        val path = asked ?: home
        if (path == "$home/Documents") throw fail.still.core.CoreException("permission", "station 不能在这里这样做", 403)
        val locked = setOf("Desktop", "Documents", "Downloads")
        val names = when (path) {
            home -> listOf(
                "Applications", "code", "Creative Cloud Files", "Desktop", "Documents", "Downloads", "Dropbox", "go", "Library", "miniconda3", "Movies",
                "Music", "node", "opt", "Parallels", "Pictures", "Projects", "Public", "Sites", "tmp", "VirtualBox VMs", "wechat-files", "Zotero",
                "备份", "工作", "书", "影视资料", "照片",
            )
            "$home/Projects" -> listOf("blog", "dotfiles", "still.fail", "zdrive")
            "$home/Projects/still.fail" -> listOf("apps", "client", "cloud", "design", "scripts", "station", "web")
            else -> emptyList()
        }
        val entries = names.map { fail.still.android.data.PickFolder(it, "$path/$it", unreadable = path == home && it in locked) }
        var at = home
        val crumbs = listOf(fail.still.android.data.DriveCrumb("主目录", home)) +
            path.removePrefix(home).split('/').filter { it.isNotEmpty() }.map { at = "$at/$it"; fail.still.android.data.DriveCrumb(it, at) }
        val places = listOf(
            fail.still.android.data.PickFolder("主目录", home),
            fail.still.android.data.PickFolder("桌面", "$home/Desktop", unreadable = true),
            fail.still.android.data.PickFolder("文稿", "$home/Documents", unreadable = true),
            fail.still.android.data.PickFolder("下载", "$home/Downloads", unreadable = true),
            fail.still.android.data.PickFolder("影片", "$home/Movies"),
            fail.still.android.data.PickFolder("音乐", "$home/Music"),
            fail.still.android.data.PickFolder("图片", "$home/Pictures"),
            fail.still.android.data.PickFolder("media", "/Volumes/media", disk = true),
            fail.still.android.data.PickFolder("Backup", "/Volumes/Backup", disk = true),
        )
        return kotlinx.serialization.json.Json.encodeToJsonElement(
            fail.still.android.data.DriveFolders.serializer(),
            fail.still.android.data.DriveFolders(path, path.substringBeforeLast('/').ifEmpty { "/" }, home, names, entries, crumbs, places),
        )
    }

    /** A hard-wrapped novel with chapters, as such files come. */
    private fun novel(): String {
        val para = "汪淼觉得，来找他的这四个人是一个奇怪的组合：两名警察和两名军人，如果那两个军人是武警还算正常，但这是两名陆军军官。他们走进来时，汪淼的目光首先落在那位年轻警官身上。"
        return (1..12).joinToString("\n\n") { n -> "第${n}章 科学边界\n" + (1..8).joinToString("\n") { "　　" + para.chunked(28).joinToString("\n") } }
    }

    @Test fun pagesLight() = pages(false)
    @Test fun pagesDark() = pages(true)

    private fun pages(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = launch(listOf(Screen.Stations, Screen.Station(st)), dark)
        rule.onNodeWithText("文件").assertIsDisplayed()
        h.record("drive-station-$tone").end()
        rule.onNodeWithText("文件").performClick(); h.settle()
        h.record("drive-roots-$tone").end()
        rule.onNodeWithText("书").performClick(); h.settle()
        rule.runOnUiThread { DriveUploads.list += DriveUpload(st, books, "", "封面.png", android.net.Uri.EMPTY).also { it.size = 4_200_000; it.sent = 1_600_000; it.state = "going" } }
        h.settle()
        h.record("drive-folder-$tone").end()
        rule.runOnUiThread { DriveUploads.list.clear() }
        rule.onNodeWithContentDescription("添加").performClick(); h.settle()
        h.record("drive-plus-$tone").end()
        rule.runOnUiThread { h.app.sheet = null }; h.settle()
        rule.onNodeWithText("三体.txt").performTouchInput { longClick() }; h.settle()
        h.record("drive-sheet-$tone").end()
        assertTrue(rule.onAllNodesWithText("重命名").fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun emptyLight() = empty(false)
    @Test fun emptyDark() = empty(true)

    private fun empty(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val owner = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, null, "")), dark, roots = emptyList())
        owner.record("drive-empty-owner-$tone").end()
    }

    @Test fun pickerLight() = picker(false)
    @Test fun pickerDark() = picker(true)

    /** The folder picker: at the home (its places over its folders), a name typed to find one, two levels down, a folder the station may not read. */
    private fun picker(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, null, "")), dark, roots = emptyList())
        rule.onNodeWithText("选择文件夹").performClick(); h.settle()
        rule.onNodeWithText("常用位置").assertIsDisplayed()
        h.record("drive-picker-home-$tone").end()
        rule.onNode(hasSetTextAction()).performTextInput("pro"); h.settle()
        h.record("drive-picker-filtered-$tone").end()
        assertTrue(rule.onAllNodesWithText("常用位置").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithText("Projects").performClick(); h.settle()
        rule.onNodeWithText("still.fail").performClick(); h.settle()
        rule.onNodeWithText("design").assertIsDisplayed()
        h.record("drive-picker-deeper-$tone").end()
        rule.onNodeWithText("主目录").performClick(); h.settle()
        rule.onNodeWithText("文稿").performClick(); h.settle()
        rule.onNodeWithText("完全磁盘访问权限", substring = true).assertIsDisplayed()
        h.record("drive-picker-denied-$tone").end()
    }

    @Test fun emptyMemberLight() = emptyMember(false)
    @Test fun emptyMemberDark() = emptyMember(true)

    private fun emptyMember(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val member = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, null, "")), dark, role = "member", roots = emptyList())
        member.record("drive-empty-member-$tone").end()
    }

    @Test fun readerLight() = reader(false)
    @Test fun readerDark() = reader(true)

    private fun reader(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, books, ""), Screen.DriveRead(st, books, "三体.txt")), dark)
        h.settle(3000)
        h.record("drive-reader-$tone").end()
        // A tap brings the bars.
        rule.onRoot().performTouchInput { click(center) }; h.settle()
        h.record("drive-reader-bars-$tone").end()
        rule.onNodeWithText("目录").performClick(); h.settle()
        h.record("drive-reader-toc-$tone").end()
        rule.onNodeWithText("第9章 科学边界").performClick(); h.settle()
        // The bars stay up under the sheets: search from the bottom one; the hits listed, one gone to, the pill.
        rule.onNodeWithText("搜索").performClick(); h.settle()
        rule.onNode(hasSetTextAction()).performTextInput("汪淼"); h.settle(2000)
        h.record("drive-reader-search-$tone").end()
        rule.onAllNodesWithText("汪淼", substring = true).filter(hasClickAction() and !hasSetTextAction()).onFirst().performClick(); h.settle()
        h.record("drive-reader-found-$tone").end()
        rule.onNodeWithText("排版").performClick(); h.settle()
        rule.onNodeWithText("绿").performClick(); h.settle()
        h.record("drive-reader-type-$tone").end()
        rule.runOnUiThread { h.app.sheet = null }; h.settle()
        // A tap takes the bars away: the page alone, on its paper.
        rule.onRoot().performTouchInput { click(center) }; h.settle()
        h.record("drive-reader-green-$tone").end()
    }

    @Test fun playerLight() = player(false)
    @Test fun playerDark() = player(true)

    private fun player(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, books, ""), Screen.DrivePlay(st, books, "E01.mp4")), dark)
        // The player plays on its own clock (real time).
        repeat(10) { Thread.sleep(200); h.settle(200) }
        h.record("drive-player-$tone").end()
    }

    /** Opened a second time, the reader's text and the player's video and subtitle come from the phone: the station is asked nothing. */
    @Test fun openedAgainFromThePhone() {
        DriveCache.clear(InstrumentationRegistry.getInstrumentation().targetContext)
        // The folder as the station has it now: each file's size and time as `drive.read` says them.
        val kinds = mapOf("三体.txt" to "text", "E01.mp4" to "video", "E01.srt" to "subtitle")
        val exact = DriveFolder(path = "", folders = 0, files = kinds.size.toLong(), countText = "${kinds.size} 个文件", entries = kinds.map { (name, kind) -> entry(name, kind, files[name]!!.size.toLong()) })
        val h = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Drive(st, books, "")), false, folder = exact)
        val reads = java.util.concurrent.atomic.AtomicInteger()
        h.fake.answer = { name, p -> if (name == "drive.read") reads.incrementAndGet(); answer(name, p) }
        fun asked(screen: Screen, opened: () -> Unit): Int {
            val before = reads.get()
            rule.runOnUiThread { h.app.push(screen) }
            opened()
            rule.runOnUiThread { h.app.pop() }; h.settle()
            return reads.get() - before
        }
        val read = {
            h.settle(3000)
            assertTrue(rule.onAllNodesWithText("汪淼", substring = true).fetchSemanticsNodes().isNotEmpty())
        }
        // The player plays on its own clock (real time).
        val play = { repeat(10) { Thread.sleep(200); h.settle(200) } }
        assertTrue(asked(Screen.DriveRead(st, books, "三体.txt"), read) > 0)
        assertEquals(0, asked(Screen.DriveRead(st, books, "三体.txt"), read))
        assertTrue(asked(Screen.DrivePlay(st, books, "E01.mp4"), play) > 0)
        assertEquals(0, asked(Screen.DrivePlay(st, books, "E01.mp4"), play))
    }
}
