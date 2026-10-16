// A station's files put into a message (screens/StationFiles.kt), on the fake core: ＋'s Station 文件 lists the places
// (the station's home and its folders pinned), a folder entered; two files and the folder as a whole ticked, then 添加
// puts them into the composer named by their path; a card tapped says where it is and switches it to a file (staged on
// the chat's station: `drive.stage`); sent, the message says where each one named is. Pictured light and dark
// (settled.png under motion/station-files-*).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Counts
import fail.still.android.data.DriveEntry
import fail.still.android.data.DriveFolder
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Overview
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class StationFilesTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val home = "/Users/alice"
    private val downloads = "/Users/alice/Downloads"
    private val topic = Topics.chat(st, ChatOf.Thread(Fixtures.THREAD))

    private val station = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
            drive = DriveRoots(listOf(DriveRoot(downloads, "下载", "ok"), DriveRoot("$home/code/acme", "acme", "ok")), anywhere = true, home = home),
        ),
    )

    private fun entry(name: String, kind: String, size: Long = 0, sizeText: String = "", time: String = "10/16") =
        DriveEntry(name, kind == "folder", size, Fixtures.NOW, if (kind == "folder") "" else "x", kind, sizeText, time)

    private fun folder(vararg entries: DriveEntry) = DriveFolder(path = "", folders = entries.count { it.dir }.toLong(), files = entries.count { !it.dir }.toLong(), countText = "", entries = entries.toList())

    private fun open(dark: Boolean): Harness {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(Fixtures.talk))
        h.fake.put(Topics.drive(st, home, ""), folder(entry("code", "folder"), entry("Desktop", "folder"), entry("Downloads", "folder"), entry("Movies", "folder")))
        h.fake.put(Topics.drive(st, home, "Downloads"), folder(
            entry("设计稿", "folder"), entry("login-375.png", "image", 319_488, "312 KB"), entry("发版录屏 1014.mp4", "video", 50_541_773, "48.2 MB"),
            entry("orders-慢查询.md", "markdown", 9_216, "9 KB"), entry("export-1013.csv", "csv", 225_280, "220 KB"),
        ))
        h.fake.answer = { name, params ->
            when (name) {
                "drive.stage" -> buildJsonObject { put("name", "orders-慢查询.md"); put("path", "uploads/orders-慢查询.md"); put("size", 9_216) }
                "chat.send" -> { h.fake.put(topic, Fixtures.chat(Fixtures.talk, listOf(Fixtures.outgoing("out-1", params["text"]!!.jsonPrimitive.content)))); JsonNull }
                else -> JsonNull
            }
        }
        h.launch(listOf(Screen.Home, Screen.Chat(st, ChatOf.Thread(Fixtures.THREAD))), dark = dark)
        // Harness.launch puts the station without its drive: the station with it again, once the app is up.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        return h
    }

    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }
    private fun tap(text: String) = rule.onAllNodesWithText(text).onFirst().performClick()

    @Test fun light() = puts(false)
    @Test fun dark() = puts(true)

    private fun puts(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        val h = open(dark)
        rule.onNode(hasContentDescription("添加到消息")).performSemanticsAction(SemanticsActions.OnClick)
        h.settle()
        picture(h, "station-files-$theme-attach")
        tap("Station 文件"); h.settle()
        rule.onNodeWithText("主目录").assertExists()
        rule.onNodeWithText("下载").assertExists()
        picture(h, "station-files-$theme-places")
        tap("主目录"); h.settle()
        tap("Downloads"); h.settle()
        tap("login-375.png"); tap("orders-慢查询.md"); tap("整个文件夹"); h.settle()
        picture(h, "station-files-$theme-ticked")
        tap("添加 3 个"); h.settle()
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
        picture(h, "station-files-$theme-composer")
        // The card of one: where it is, how it goes; switched to a file, staged on the chat's station.
        tap("orders-慢查询.md"); h.settle()
        rule.onNodeWithText("发送方式").assertExists()
        picture(h, "station-files-$theme-card")
        tap("文件"); h.settle()
        val staged = h.fake.calls.last { it.first == "drive.stage" }.second
        assertEquals(home, staged["root"]!!.jsonPrimitive.content)
        assertEquals("Downloads/orders-慢查询.md", staged["path"]!!.jsonPrimitive.content)
        rule.runOnUiThread { h.app.sheet = null }
        h.settle()
        picture(h, "station-files-$theme-switched")
        rule.onNode(hasContentDescription("发送")).performSemanticsAction(SemanticsActions.OnClick)
        h.settle()
        val sent = h.fake.calls.last { it.first == "chat.send" }.second
        val text = sent["text"]!!.jsonPrimitive.content
        assertTrue(text, text.contains("$downloads/login-375.png"))
        assertTrue(text, text.contains(downloads))
        assertTrue(text, !text.contains("orders-慢查询.md"))
        assertEquals("uploads/orders-慢查询.md", sent["attachments"].toString().let { Regex("\"path\":\"([^\"]+)\"").find(it)?.groupValues?.get(1) })
    }
}
