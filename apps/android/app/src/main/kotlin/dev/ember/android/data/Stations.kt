// The `stations` view (docs/client-core.md → Views): every station of a
// workspace with its link, overview (profiles, connects) and host. Shapes
// follow web/src/api.ts (StationView) and src/admin/types.ts.
package dev.ember.android.data

import kotlinx.serialization.Serializable

@Serializable data class LinkView(val state: String = "connecting", val message: String? = null)

/** A quota window, as the core puts it: its mark (5H, W), what is left, how full (ok | amber | red), when it refills. */
@Serializable data class QuotaWindow(
    val label: String, val usedPercent: Double, val resetsAt: Long? = null,
    val mark: String = "", val left: Int = 100, val level: String = "ok", val refills: String? = null,
)
/** Its windows shortest first (the core's order). */
@Serializable data class ProfileQuota(val state: String, val windows: List<QuotaWindow> = emptyList(), val detail: String? = null)
@Serializable data class ProfileCheck(val state: String, val detail: String = "", val models: List<String>? = null, val time: Map<String, Stamp> = emptyMap())

@Serializable data class ProfileView(
    val id: String,
    val name: String,
    val runtime: String = "claude",
    /** Enabled for use: only these can be chosen for chats. */
    val models: List<String> = emptyList(),
    val check: ProfileCheck? = null,
    val quota: ProfileQuota? = null,
    /** Its last check in words, and its tone. */
    val checkText: String = "",
    val checkTone: String = "neutral",
    /** The makers of its models, and of those its check found, by model. */
    val makers: Map<String, Maker?> = emptyMap(),
) {
    /** What can be enabled: what the provider lists, and whatever is enabled already. */
    val available: List<String> get() = ((check?.models ?: emptyList()) + models).distinct()
}

@Serializable data class SlackIdentity(val url: String? = null, val team: String? = null)
@Serializable data class ConnectState(val state: String, val workspace: SlackIdentity? = null, val botUserId: String? = null, val error: String? = null)

@Serializable data class ConnectView(
    val id: String,
    val name: String,
    val kind: String = "slack",
    val enabled: Boolean = true,
    val connection: ConnectState = ConnectState("disabled"),
    /** Its link to Slack in words and as a dot (online | busy | error | offline); how it runs in words. */
    val statusText: String = "",
    val presence: String = "offline",
    val modeText: String = "",
    val runText: String = "",
)

@Serializable data class Counts(val sessions: Int = 0, val running: Int = 0, val warm: Int = 0)

@Serializable data class Overview(
    val connects: List<ConnectView> = emptyList(),
    val profiles: List<ProfileView> = emptyList(),
    val counts: Counts = Counts(),
    /** The Slack users the viewer said are them: the station takes them for the viewer. */
    val slackUsers: List<String> = emptyList(),
    /** Its agents' processes, in a line. */
    val processesText: String? = null,
)

@Serializable data class Memory(val totalBytes: Long, val usedBytes: Long)
@Serializable data class Disk(val totalBytes: Long, val freeBytes: Long)
/** CPU, memory or disk: how full (and how bad: ok | amber | red), in words. */
@Serializable data class Meter(val label: String, val short: String = "", val percent: Int = 0, val level: String = "ok", val value: String = "", val note: String? = null)

@Serializable data class HostInfo(
    val hostname: String,
    val os: String = "",
    val cpus: Int = 0,
    val cpuModel: String = "",
    /** 1-minute load per CPU, 0–1+. */
    val load: Double = 0.0,
    val uptimeSec: Long = 0,
    val memory: Memory,
    val disk: Disk,
    /** In words, as the core puts it: 8 核 · 32 GB; macOS · 8 核 · 32 GB · 已运行 3 天; what it is; how loaded. */
    val summary: String = "",
    val line: String = "",
    val facts: List<String> = emptyList(),
    val meters: List<Meter> = emptyList(),
    val emberText: String = "",
)

@Serializable data class RuntimeModels(val runtime: String, val models: List<String> = emptyList())

/** A model the station can run, with the runtimes it runs on (the core's): the model is chosen first, the runtime only when there are several. */
@Serializable data class ModelRuntimes(
    val model: String,
    val maker: Maker? = null,
    val runtimes: List<String> = emptyList(),
    /** For each runtime: how hard it can think, and who runs it there. */
    val efforts: Map<String, List<String>> = emptyMap(),
    val accounts: Map<String, List<RunnableProfile>> = emptyMap(),
    val spent: Spent? = null,
)

/** Every account that runs a model has a window used up: when the first of them refills (ms), if known; in words. */
@Serializable data class Spent(val until: Double? = null, val text: String = "", val back: String? = null)

@Serializable data class StationView(
    val station: String,
    val id: String,
    val name: String,
    /** Its line in a list, as the core puts it: offline since when, or what it is and whether its agents work. */
    val summary: String = "",
    val online: Boolean = false,
    /** Seconds, from ember cloud. */
    val lastSeen: Long? = null,
    val version: String? = null,
    val link: LinkView = LinkView(),
    val overview: Overview? = null,
    val host: HostInfo? = null,
    val runtimes: List<RuntimeModels> = emptyList(),
    val models: List<ModelRuntimes> = emptyList(),
    val time: Map<String, Stamp> = emptyMap(),
)
