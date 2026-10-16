// A station's memory (screens/Memory.kt) on the fake core: the list (the global memory by its parts, a row per project
// and skill, the station's own folded in a row and opened), a project's page with its files picked between, and a part
// of the global memory. Each is pictured light and dark (settled.png under motion/memory-*).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.MemoryFile
import fail.still.android.data.MemorySection
import fail.still.android.data.SkillDoc
import fail.still.android.data.SkillFile
import fail.still.android.data.StationMemory
import fail.still.android.data.StillFailJson
import kotlinx.serialization.json.JsonNull
import org.junit.Rule
import org.junit.Test

class MemoryTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION

    private fun skill(name: String, about: String, brief: String, size: String, body: String, project: Boolean = true, builtin: Boolean = false, files: List<SkillDoc> = emptyList()) =
        SkillFile(name, if (project) "项目记忆：$about" else about, project, builtin, body, body, about, brief = brief, size = size, files = files)

    private val memory = StationMemory(
        MemoryFile(
            "/Users/alice/.stillfail/agent/MEMORY.md", "", size = "12 KB",
            sections = listOf(
                MemorySection("回复和沟通", "- 回复始终用用户的语言。\n- 对比、数据用 Markdown 表格。\n- 回答「为什么」只说查到的事实。", "10 条"),
                MemorySection("做事节奏", "- 授权范围内一路做到底。\n- 不干等：CI 在跑时做下一项。", "11 条"),
                MemorySection("CI 和测试", "- 等 CI 的监视脚本任一项失败立刻退出。", "9 条"),
                MemorySection("机器", "- 本机不编译、不跑测试。", "7 条"),
            ),
        ),
        listOf(
            skill("acme-api", "Acme 的订单 API（Go + Postgres）。改接口、查慢查询时使用。", "Acme 的订单 API。改接口、查慢查询时使用。", "51 KB", "- 迁移脚本放 `db/migrations`。"),
            skill(
                "acme-web", "Acme 的 Web 前端（React + Vite）。改前端、查线上前端问题时使用。", "Acme 的 Web 前端。改前端、查线上前端问题时使用。", "147 KB",
                "# acme-web\n\n只跟 acme-web 有关的约定；细节按主题分在同目录的文件里。",
                files = listOf(
                    SkillDoc("build.md", "# 编译\n\n- 本地起：`pnpm dev`，端口 5173。", "build", "10 KB"),
                    SkillDoc("design.md", "# 设计\n\n- 卡片无描边，圆角 22。\n- 只有异常值上色。", "design", "34 KB"),
                    SkillDoc("release.md", "# 发布\n\n- 合进 main 后自动发到 staging。", "release", "9 KB"),
                ),
            ),
            skill("domain-lookup", "查域名能不能注册、多少钱时使用。", "查域名能不能注册、多少钱时使用。", "1 KB", "- 先查 whois。", project = false),
            skill("stillfail-jobs", "Run background jobs and web services.", "Run background jobs and web services.", "5 KB", "# Jobs", project = false, builtin = true),
            skill("stillfail-show", "Show evidence of visible work.", "Show evidence of visible work.", "3 KB", "# Show", project = false, builtin = true),
        ),
    )

    private fun launch(stack: List<Screen>, dark: Boolean): Harness {
        val h = Harness(rule)
        h.fake.answer = { name, _ -> if (name == "memory.get") StillFailJson.encodeToJsonElement(StationMemory.serializer(), memory) else JsonNull }
        h.launch(stack, dark)
        return h
    }

    @Test fun pagesLight() = pages(false)
    @Test fun pagesDark() = pages(true)

    private fun pages(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = launch(listOf(Screen.Stations, Screen.Station(st), Screen.Memory(st)), dark)
        rule.onNodeWithText("回复和沟通").assertIsDisplayed()
        h.record("memory-list-$tone").end()
        rule.onNodeWithText("station 自带").performClick(); h.settle()
        rule.onNodeWithText("stillfail-show").assertIsDisplayed()
        h.record("memory-builtin-$tone").end()
        rule.onNodeWithText("acme-web").performClick(); h.settle()
        rule.onNodeWithText("分享给其他 station").assertIsDisplayed()
        h.record("memory-skill-$tone").end()
        rule.onNodeWithText("design", substring = true).performClick(); h.settle()
        rule.onNodeWithText("只有异常值上色。", substring = true).assertIsDisplayed()
        h.record("memory-file-$tone").end()
        rule.runOnUiThread { h.app.pop() }; h.settle()
        rule.onNodeWithText("做事节奏").performClick(); h.settle()
        rule.onNodeWithText("不干等", substring = true).assertIsDisplayed()
        h.record("memory-global-$tone").end()
    }
}
