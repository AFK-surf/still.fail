package fail.still.android.data

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/// What the bar's timing (BarTiming, in the app) hears of the topics followed here: this module does not see the app, so
/// the app says where it goes when it starts (BarTiming.start); before that, nowhere.
object TopicTiming {
    var followed: (topic: JsonObject, held: Boolean) -> Unit = { _, _ -> }
    var decoded: (topic: JsonObject, arrived: Long, value: JsonElement?, failed: Boolean) -> Unit = { _, _, _, _ -> }
    var shown: (topic: JsonObject, value: Any?, failed: Boolean) -> Unit = { _, _, _ -> }
}
