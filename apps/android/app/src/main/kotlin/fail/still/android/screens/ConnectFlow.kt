package fail.still.android.screens

import androidx.compose.runtime.*
import fail.still.android.AppState
import fail.still.android.data.ConnectFlowView
import fail.still.android.data.rememberTopic
import kotlinx.serialization.json.*

/** UI adapter only: the core owns the steps, draft, model choices and writes. */
internal class ConnectFlow(private val app: AppState, val station: String, val form: String) {
    var view by mutableStateOf<ConnectFlowView?>(null)
    private val calls = setOf("config", "make", "verify", "create").map { "connect.flow.$it" }.toSet()
    val busy get() = app.isDoing(calls, "station" to station, "form" to form)
    val error get() = app.failedOf(calls, "station" to station, "form" to form)
    suspend fun call(action: String, input: JsonObject = buildJsonObject {}) = app.core.call("connect.flow.$action", buildJsonObject {
        put("station", station); put("form", form); put("input", input)
    })
    fun edit(fill: JsonObjectBuilder.() -> Unit) { app.act("修改连接草稿") { call("edit", buildJsonObject(fill)) } }
    fun go(to: String, close: () -> Unit = {}) { app.act("切换步骤") { if (call("go", buildJsonObject { put("to", to) }).jsonObject["close"]?.jsonPrimitive?.booleanOrNull == true) close() } }
    fun act(action: String, done: (JsonObject) -> Unit = {}) {
        if (!busy) app.act("${view?.title ?: "添加连接"}") { done(call(action).jsonObject) }
    }
    fun choose(fill: JsonObjectBuilder.() -> Unit) { app.act("选择模型") {
        app.api(station).pickSet("connect-new:$form", fill); app.api(station).pickSave("connect-new:$form")
    } }
}

@Composable
internal fun rememberConnectFlow(app: AppState, station: String, resume: String?): ConnectFlow {
    val flow = remember(app.core, station) { ConnectFlow(app, station, java.util.UUID.randomUUID().toString()) }
    val topic by rememberTopic<ConnectFlowView>(app.core, buildJsonObject { put("topic", "connectFlow"); put("station", station); put("form", flow.form) })
    flow.view = topic.value
    LaunchedEffect(flow, resume) { app.act("打开连接草稿") { flow.call("open", buildJsonObject { put("mobile", true); put("resume", resume) }) } }
    DisposableEffect(flow) { onDispose { app.act("关闭连接草稿") { flow.call("drop") } } }
    return flow
}
