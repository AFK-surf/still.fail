package fail.still.core

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlinx.serialization.json.JsonObject

/** Lets a UI callback identify its named calls without repeating their parameters in the view.
 * Inherited by child coroutines, isolated from other actions. Does not own any operation state. */
class CallObserver(val started: (String, JsonObject) -> Unit) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<CallObserver>
}
