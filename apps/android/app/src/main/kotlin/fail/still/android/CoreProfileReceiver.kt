// What the core spends its time on, asked from adb: only the shell (DUMP) may send it.
//   adb shell am broadcast -n <app id>/fail.still.android.CoreProfileReceiver --ei seconds 60
// writes Android/data/<app id>/files/core-<time>.cpuprofile once the time is up (logcat StillFailCore says so).
package fail.still.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import fail.still.core.CoreProfile
import java.io.File

class CoreProfileReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val seconds = intent.getIntExtra("seconds", 60).coerceIn(1, 600)
        val dir = context.getExternalFilesDir(null) ?: return
        CoreProfile.sample(seconds, File(dir, "core-${System.currentTimeMillis()}.cpuprofile").path)
    }
}
