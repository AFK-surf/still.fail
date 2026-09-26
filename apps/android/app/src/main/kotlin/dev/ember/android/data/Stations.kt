// The `stations` view (docs/client-core.md → Views): every station of a
// workspace with its link, overview (profiles, connects) and host. Shapes
// follow web/src/api.ts (StationView) and src/admin/types.ts.
package dev.ember.android.data

import kotlinx.serialization.Serializable

@Serializable data class LinkView(val state: String = "connecting", val message: String? = null)

@Serializable data class QuotaWindow(val label: String, val usedPercent: Double, val resetsAt: Long? = null)
@Serializable data class ProfileQuota(val state: String, val windows: List<QuotaWindow> = emptyList(), val detail: String? = null)
@Serializable data class ProfileCheck(val state: String, val detail: String = "", val models: List<String>? = null)

@Serializable data class ProfileView(
    val id: String,
    val name: String,
    val runtime: String = "claude",
    /** Enabled for use: only these can be chosen for chats. */
    val models: List<String> = emptyList(),
    val check: ProfileCheck? = null,
    val quota: ProfileQuota? = null,
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
) {
    private val live: Boolean get() = connection.state == "connected" || connection.state == "reconnecting"
    /** Its bot's Slack user, while connected: how `<@U…>` mentions of it are named. */
    val botUserId: String? get() = connection.botUserId?.takeIf { live }
}

@Serializable data class Counts(val sessions: Int = 0, val running: Int = 0, val warm: Int = 0)

@Serializable data class Overview(
    val connects: List<ConnectView> = emptyList(),
    val profiles: List<ProfileView> = emptyList(),
    val counts: Counts = Counts(),
    /** The Slack users the viewer said are them: the station takes them for the viewer. */
    val slackUsers: List<String> = emptyList(),
)

@Serializable data class Memory(val totalBytes: Long, val usedBytes: Long)
@Serializable data class Disk(val totalBytes: Long, val freeBytes: Long)

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
) {
    val cpuPercent: Int get() = (load * 100).toInt().coerceIn(0, 100)
    val memPercent: Int get() = if (memory.totalBytes > 0) (memory.usedBytes * 100 / memory.totalBytes).toInt() else 0
    val diskPercent: Int get() = if (disk.totalBytes > 0) ((disk.totalBytes - disk.freeBytes) * 100 / disk.totalBytes).toInt() else 0
}

@Serializable data class RuntimeModels(val runtime: String, val models: List<String> = emptyList())

@Serializable data class StationView(
    val station: String,
    val id: String,
    val name: String,
    val online: Boolean = false,
    /** Seconds, from ember cloud. */
    val lastSeen: Long? = null,
    val version: String? = null,
    val link: LinkView = LinkView(),
    val overview: Overview? = null,
    val host: HostInfo? = null,
    val runtimes: List<RuntimeModels> = emptyList(),
)
