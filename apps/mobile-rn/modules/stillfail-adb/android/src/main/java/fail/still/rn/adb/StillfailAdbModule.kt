package fail.still.rn.adb

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/**
 * AdbShare (AdbShare.kt) for the page in JavaScript (screens/AdbShare.tsx): what the phone has for Wireless debugging,
 * the ways to Settings, and the lending started. The other way, the core the service asks of (Core): `call`, `follow`
 * and `unfollow` events, made by index.ts `serve`, which says back what came of them (`answer`, `value`). `wireless`:
 * Wireless debugging switched (by the app, or by Android as the Wi-Fi goes).
 */
class StillfailAdbModule : Module() {
  private val context: Context get() = appContext.reactContext ?: throw IllegalStateException("no Android context")
  /** Settings opened from the app: from its activity while there is one, as the Android app's page does. */
  private val opener: Context get() = appContext.currentActivity ?: context
  private var observer: ContentObserver? = null

  override fun definition() = ModuleDefinition {
    Name("StillfailAdb")
    Events("call", "follow", "unfollow", "wireless")

    OnCreate {
      val watch = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) { sendEvent("wireless", emptyMap<String, Any?>()) }
      }
      val resolver = appContext.reactContext?.contentResolver ?: return@OnCreate
      resolver.registerContentObserver(AdbShare.wirelessUri(), false, watch)
      observer = watch
    }

    OnDestroy {
      observer?.let { watch -> appContext.reactContext?.contentResolver?.unregisterContentObserver(watch) }
      observer = null
      Core.gone(this@StillfailAdbModule)
    }

    Function("supported") { AdbShare.supported }

    Function("start") { station: String, name: String, words: Map<String, String> ->
      AdbShare.words = words
      AdbShare.start(context, station, name)
    }

    Function("developerOptions") { AdbShare.developerOptions(context) }
    Function("wirelessOn") { AdbShare.wirelessOn(context) }
    Function("canSwitch") { AdbShare.canSwitch(context) }
    Function("switchOn") { AdbShare.switchOn(context) }
    Function("onWifi") { AdbShare.onWifi(context) }
    Function("openWireless") { beside: Boolean -> AdbShare.openWireless(opener, beside) }
    Function("reads") { AdbShare.reads(context) }
    Function("openReader") { AdbShare.openReader(opener) }

    Function("ready") { Core.ready(this@StillfailAdbModule) }
    Function("answer") { id: Int, error: String? -> Core.answer(id, error) }
    Function("value") { id: Int, json: String? -> Core.value(id, json) }
  }

  internal fun say(event: String, body: Map<String, Any?>) {
    sendEvent(event, body)
  }
}
