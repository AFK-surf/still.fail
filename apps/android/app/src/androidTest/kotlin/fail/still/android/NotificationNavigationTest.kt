package fail.still.android

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.data.ChatOf
import fail.still.android.motion.FakeCore
import kotlinx.coroutines.cancel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Test

/** Navigation on a core-parsed notification URL, without connecting to a live station. */
class NotificationNavigationTest {
    private fun check(notification: Boolean, alreadyOpen: Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val fake = FakeCore()
        fake.answer = { name, _ ->
            if (name == "link.parse") Json.parseToJsonElement(
                """{"opens":"item","workspace":"destination","station":"station","session":"chat"}"""
            ) else JsonNull
        }
        lateinit var app: AppState
        instrumentation.runOnMainSync {
            val prefs = context.getSharedPreferences("notification-navigation-test", Context.MODE_PRIVATE)
            prefs.edit().clear().commit()
            app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", fake.core))
            app.pickWorkspace("previous")
            if (alreadyOpen) app.push(Screen.Chat("previous/station", ChatOf.Session("previous-chat")))
            app.openLink("http://127.0.0.1:9/o/destination/station/chat", outside = true, notification = notification)
        }
        try {
            val expected = if (notification) listOf(Screen.Home, Screen.Decisions)
                else listOf(Screen.Home, Screen.Chat("destination/station", ChatOf.Session("chat")))
            var arrived = false
            repeat(100) {
                if (!arrived) {
                    Thread.sleep(20)
                    instrumentation.runOnMainSync { arrived = app.stack == expected && app.workspace == "destination" }
                }
            }
            instrumentation.runOnMainSync {
                assertEquals("notification workspace", "destination", app.workspace)
                assertEquals("landing page and back stack", expected, app.stack)
                app.pop()
                assertEquals("back returns to the list", listOf(Screen.Home), app.stack)
            }
        } finally {
            instrumentation.runOnMainSync { app.scope.cancel() }
        }
    }

    @Test fun notificationFromHome() = check(notification = true, alreadyOpen = false)
    @Test fun notificationReplacesAnotherChatAndWorkspace() = check(notification = true, alreadyOpen = true)
    @Test fun ordinaryLinkStillOpensChat() = check(notification = false, alreadyOpen = true)
}
