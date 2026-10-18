// The share list's second entry (the manifest's `.share.Quick` alias of ShareActivity, docs/client-plugins.md): on
// while the person has a plugin with a share entry in the workspace open in the app, off otherwise, so nobody without
// one sees it in their share list.
package fail.still.android.share

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import fail.still.android.data.PluginsView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.core.StillFailCore
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull

object Quick {
    private const val ALIAS = "fail.still.android.share.Quick"

    /** Whether a share came in through this entry. */
    fun isIt(intent: Intent?): Boolean = intent?.component?.className == ALIAS

    fun set(context: Context, on: Boolean) {
        val pm = context.packageManager
        val name = ComponentName(context.packageName, ALIAS)
        val want = if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        // Disabled by default in the manifest: the default state is off.
        val now = pm.getComponentEnabledSetting(name).let { if (it == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) PackageManager.COMPONENT_ENABLED_STATE_DISABLED else it }
        if (now != want) runCatching { pm.setComponentEnabledSetting(name, want, PackageManager.DONT_KILL_APP) }
    }

    /** Keeps the entry as the workspace's plugins say, while it is followed. */
    suspend fun follow(context: Context, core: StillFailCore, workspace: String) {
        core.topic(Topics.plugins(workspace))
            .mapNotNull { s -> s.value?.let { v -> runCatching { decode(PluginsView.serializer(), v) }.getOrNull() } }
            .map { view -> view.items.any { p -> p.entries.any { it.kind == "share" } } }
            .distinctUntilChanged()
            .collect { set(context, it) }
    }
}
