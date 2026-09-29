// What the app makes of the core's marks. Every shape the core sends is in Shapes.kt, generated from client/shapes
// (scripts/shapes.sh): nothing of it is written here.
package fail.still.android.data

/** Where an agent stands, as its badge shows it: solid orange block, hollow ring at work, red failed; done has none. */
enum class ChatState { Block, Running, Done, Failed }

/** A badge the core names (block | run | failed) as the app's state. */
fun badgeState(badge: Badge?): ChatState? = when (badge) {
    "block" -> ChatState.Block; "run" -> ChatState.Running; "failed" -> ChatState.Failed; else -> null
}

val Session.state: ChatState get() = badgeState(mark) ?: ChatState.Done
val RowAgent.state: ChatState get() = badgeState(mark) ?: ChatState.Done
val ChatAgent.state: ChatState get() = badgeState(badge) ?: ChatState.Done

/** What can be enabled on a profile: what its provider lists, and whatever is enabled already. */
val Profile.available: List<String> get() = ((check?.models ?: emptyList()) + models).distinct()
