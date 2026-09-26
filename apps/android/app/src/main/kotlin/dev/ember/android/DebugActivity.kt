package dev.ember.android

import android.app.Activity
import android.os.Bundle
import android.system.Os
import android.util.Base64
import android.util.Log
import android.widget.ScrollView
import android.widget.TextView
import dev.ember.core.EmberCore
import dev.ember.core.TopicState
import java.util.TimeZone
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Runs the core end to end and shows what it saw (also in logcat, tag
 * EmberDebug). Extras: `cloud` (the cloud origin, default
 * https://ember.3720.org) and `account` (base64 of an account as the dev
 * cloud's /__dev/account gives it, handed to the core with `migrate`).
 */
class DebugActivity : Activity() {
    private val scope: CoroutineScope = MainScope()
    private lateinit var text: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        text = TextView(this).apply { setPadding(32, 96, 32, 32); textSize = 12f }
        setContentView(ScrollView(this).apply { addView(text) })
        val cloud = intent.getStringExtra("cloud") ?: "https://ember.3720.org"
        val account = intent.getStringExtra("account")?.let { String(Base64.decode(it, Base64.DEFAULT)) }
        scope.launch {
            try {
                run(cloud, account)
            } catch (e: Exception) {
                say("FAILED ${e::class.simpleName}: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun run(cloud: String, account: String?) {
        for (at in listOf(1_767_225_600_000L, 1_782_864_000_000L, System.currentTimeMillis())) {
            val core = dev.ember.core.ffi.utcOffsetMin(at.toDouble())
            say("utc offset at $at: core $core, java ${TimeZone.getDefault().getOffset(at) / 60_000} (${TimeZone.getDefault().id})")
        }
        // The same through a zone with DST (TZ overrides the system zone for the C library only).
        Os.setenv("TZ", "Europe/Berlin", true)
        say("Europe/Berlin: winter ${dev.ember.core.ffi.utcOffsetMin(1_767_225_600_000.0)}, summer ${dev.ember.core.ffi.utcOffsetMin(1_782_864_000_000.0)}")
        Os.unsetenv("TZ")
        val core = EmberCore.start(this, cloud)
        say("core started against $cloud")
        if (account != null) {
            core.call("migrate", buildJsonObject { put("accounts", buildJsonArray { add(Json.parseToJsonElement(account)) }) })
            say("migrated an account")
        }
        say("accounts: ${settled(core, obj("accounts")).brief()}")
        val begin = core.call("auth.begin", buildJsonObject {
            put("redirect_uri", "ember://auth/callback"); put("return_to", "/"); put("device_name", "Android")
        })
        say("auth.begin: $begin")
        val workspaces = settled(core, obj("workspaces"))
        say("workspaces: ${workspaces.brief()}")
        val workspace = workspaces.value?.jsonArray?.firstOrNull()?.jsonObject?.get("workspaces")?.jsonArray?.firstOrNull()?.jsonObject
            ?: return say("DONE (no workspace)")
        val id = workspace.getValue("id").jsonPrimitive.content
        say("stations of $id:")
        // Until a station is online with its overview read (or a minute passes).
        val stations = withTimeout(60_000) {
            core.topic(obj("stations", "scope" to id)).first { state ->
                say("  ${state.brief()}")
                state.value?.jsonArray?.any { it.jsonObject["overview"] is JsonObject } == true
            }
        }
        val station = stations.value!!.jsonArray.first { it.jsonObject["overview"] is JsonObject }.jsonObject
        val address = station.getValue("station").jsonPrimitive.content
        say("sessions of $address: ${settled(core, obj("sessions", "station" to address)).brief()}")
        say("chats: ${settled(core, obj("chats", "scope" to id)).brief()}")
        say("DONE")
    }

    private suspend fun settled(core: EmberCore, topic: JsonObject): TopicState =
        withTimeout(60_000) { core.topic(topic).first { !it.loading } }

    private fun obj(topic: String, vararg params: Pair<String, String>) = buildJsonObject {
        put("topic", topic)
        for ((k, v) in params) put(k, v)
    }

    private fun TopicState.brief(): String =
        error?.let { "error ${it.code}: ${it.message}" } ?: value.toString().take(600)

    private fun say(line: String) {
        Log.i("EmberDebug", line)
        runOnUiThread { text.append(line + "\n") }
    }
}
