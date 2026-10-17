// Installing an APK (an update of the app, a file a chat has): the system's installer, asked; what it says.
package fail.still.android

import fail.still.android.data.t
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import fail.still.android.data.AppRelease
import fail.still.android.data.StillFailJson
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Whether this app may install apps (安装未知应用); when not, the system's page for it opens instead. */
fun mayInstall(context: Context): Boolean {
    if (context.packageManager.canRequestPackageInstalls()) return true
    context.startActivity(
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
    return false
}

/**
 * Hands an APK to the system's installer; what it says comes to [InstallResult], which opens its page for the person
 * to confirm. `self`: this app's own newer build, installed over it without asking where the system allows that.
 */
fun installApk(context: Context, apk: File, self: Boolean = false) {
    val installer = context.packageManager.packageInstaller
    val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
        if (self) {
            setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        setSize(apk.length())
    }
    val id = installer.createSession(params)
    installer.openSession(id).use { session ->
        session.openWrite("stillfail.apk", 0, apk.length()).use { out ->
            apk.inputStream().use { it.copyTo(out) }
            session.fsync(out)
        }
        val intent = Intent(context, InstallResult::class.java).putExtra(InstallResult.SELF, self)
        // The installer puts its status in the intent: it has to be mutable.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        session.commit(PendingIntent.getBroadcast(context, id, intent, flags).intentSender)
    }
}

class InstallResult : BroadcastReceiver() {
    companion object { const val SELF = "self" }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else intent.getParcelableExtra(Intent.EXTRA_INTENT)) ?: return
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            PackageInstaller.STATUS_FAILURE_ABORTED -> Unit
            else -> {
                KeptLang.words(context)
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: t("android-misc.updates.installFailed")
                val words = if (intent.getBooleanExtra(SELF, true)) "android-misc.updates.failed" else "android-chat.file.installFailed"
                Toast.makeText(context, t(words, "error" to message), Toast.LENGTH_LONG).show()
            }
        }
    }
}
