package fail.still.android.screens

import androidx.compose.runtime.*
import fail.still.android.AppState
import fail.still.android.data.UNTRACKED_OPERATIONS
import fail.still.core.CallObserver
import fail.still.core.CoreException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

/** Callback adapter. The core supplies running/failed state; only native work without a core call is local. */
internal open class Action(private val app: AppState) {
    private data class Call(val name: String, val on: List<Pair<String, String>>)
    private var calls by mutableStateOf<List<Call>>(emptyList())
    private var nativePending by mutableStateOf(false)
    private var locked = false
    var error by mutableStateOf<CoreException?>(null)
        private set
    val busy get() = calls.filter { it.name !in UNTRACKED_OPERATIONS }.let { tracked ->
        if (tracked.isEmpty()) nativePending else tracked.any { app.isDoing(it.name, *it.on.toTypedArray()) }
    }
    fun run(work: suspend () -> Unit) {
        if (locked) return
        locked = true; calls = emptyList(); nativePending = true; error = null
        app.scope.launch {
            try {
                withContext(CallObserver { name, params ->
                    val on = params.mapNotNull { (key, value) ->
                        if (Regex("token|code|password|secret", RegexOption.IGNORE_CASE).containsMatchIn(key)) null
                        else (value as? JsonPrimitive)?.takeIf { it !is JsonNull }?.let { key to it.content }
                    }
                    calls = calls + Call(name, on)
                }) { work() }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                error = e as? CoreException ?: CoreException("local", e.message ?: e.toString(), null)
                app.toast = error!!.message
            } finally { locked = false; nativePending = false }
        }
    }
}
