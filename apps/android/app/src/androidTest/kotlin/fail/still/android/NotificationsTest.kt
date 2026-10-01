package fail.still.android

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.data.Notice
import fail.still.android.data.NotifyView
import fail.still.android.data.Topics
import fail.still.android.motion.FakeCore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Test

/** The real Android delivery path, with only the core's transport scripted. */
class NotificationsTest {
    @Test fun block_and_completion_reach_the_system_and_open_their_chat() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        val fake = FakeCore()
        fake.answer = { name, _ -> buildJsonObject { if (name == "notice.claim") put("show", true) } }
        val prefs = context.getSharedPreferences("notification-test", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val app = withContext(Dispatchers.Main) {
            AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", fake.core))
        }
        val topic = Topics.notify(app.workspace)
        val job = launch(Dispatchers.Main) { showNotices(context, app) }
        val tag = "notification-test/st/chat"
        try {
            withTimeout(5000) { while (!fake.subscribed(topic)) delay(20) }
            for ((index, kind) in listOf("block", "done").withIndex()) {
                val notice = Notice("test-$index", kind, "notification-test/st", "notification-test", "st", "chat", 7,
                    "另一段对话", if (kind == "block") "需要处理 · 请确认" else "任务完成", tag, "/o/notification-test/st/chat", System.currentTimeMillis())
                fake.put(topic, NotifyView(true, true, true, listOf(notice)))
                withTimeout(5000) {
                    while (manager.activeNotifications.none { it.tag == tag && it.notification.extras.getString("android.text") == notice.body }) delay(20)
                }
                val shown = manager.activeNotifications.single { it.tag == tag }
                assertEquals("另一段对话", shown.notification.extras.getString("android.title"))
                assertEquals(1, manager.activeNotifications.count { it.tag == tag })
                check(shown.notification.contentIntent != null)
            }
            assertEquals(2, fake.calls.count { it.first == "notice.claim" })
        } finally {
            job.cancelAndJoin()
            manager.cancel(tag, 1)
        }
    }
}
