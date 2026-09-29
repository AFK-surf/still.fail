// The app keeps itself current: ember cloud says which build is the latest (/releases/android/latest.json, put there
// by scripts/release.sh), and a newer one is downloaded, checked against its sha256 and handed to the system's
// installer, which installs it over this one (the same package and signing key) once the person agrees.
package dev.ember.android

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
import dev.ember.android.data.EmberJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** A build of the app on ember cloud: `file` is under /releases/. */
@Serializable
data class Release(val versionCode: Long, val versionName: String, val file: String, val sha256: String, val size: Long)

class Updates(context: Context, private val origin: String) {
    private val context = context.applicationContext
    /** A build newer than this one, once a check found it. */
    var available by mutableStateOf<Release?>(null); private set
    /** What an update under way is doing ("下载中 40%"), null when none is. */
    var progress by mutableStateOf<String?>(null); private set
    private var checkedAt = 0L

    /** Asks ember cloud for the latest build, at most once an hour unless `now`; the newer one it finds, if any. */
    suspend fun check(now: Boolean = false): Release? {
        val time = System.currentTimeMillis()
        if (!now && time - checkedAt < 60 * 60 * 1000) return null
        checkedAt = time
        val latest = try {
            withContext(Dispatchers.IO) {
                val connection = URL("$origin/releases/android/latest.json").openConnection() as HttpURLConnection
                connection.connectTimeout = 10_000
                connection.readTimeout = 10_000
                connection.useCaches = false
                try {
                    if (connection.responseCode != 200) null
                    else EmberJson.decodeFromString(Release.serializer(), connection.inputStream.bufferedReader().readText())
                } finally {
                    connection.disconnect()
                }
            }
        } catch (e: Exception) {
            null
        } ?: return null
        if (latest.versionCode <= BuildConfig.VERSION_CODE) return null
        available = latest
        return latest
    }

    /**
     * Downloads the newer build and hands it to the installer. Installing apps needs the person's leave (安装未知应用):
     * without it the system's page for it opens instead, and they tap 更新 again once it is given. A failure is said.
     */
    suspend fun install(): String? {
        val release = available ?: return null
        if (progress != null) return null
        if (!context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "允许 still.fail 安装应用后，再点一次更新"
        }
        return try {
            progress = "下载中"
            val apk = download(release)
            progress = "正在安装"
            withContext(Dispatchers.IO) { commit(apk) }
            null
        } catch (e: Exception) {
            "没能更新：${e.message ?: e.javaClass.simpleName}"
        } finally {
            progress = null
        }
    }

    private suspend fun download(release: Release): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val apk = File(dir, "ember-${release.versionCode}.apk")
        val digest = MessageDigest.getInstance("SHA-256")
        val connection = URL("$origin/releases/${release.file}").openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
            if (connection.responseCode != 200) error("下载返回了 ${connection.responseCode}")
            connection.inputStream.use { input ->
                apk.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    var shown = -1L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                        done += read
                        val percent = if (release.size > 0) done * 100 / release.size else -1
                        if (percent != shown) {
                            shown = percent
                            withContext(Dispatchers.Main) { progress = if (percent >= 0) "下载中 $percent%" else "下载中" }
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
        val sum = digest.digest().joinToString("") { "%02x".format(it) }
        if (!sum.equals(release.sha256, ignoreCase = true)) {
            apk.delete()
            error("下载的文件不完整，请重试")
        }
        apk
    }

    private fun commit(apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            session.openWrite("ember.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(context, InstallResult::class.java)
            // The installer puts its status in the intent: it has to be mutable.
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getBroadcast(context, id, intent, flags).intentSender)
        }
    }
}

/** What the installer says of a commit: it wants the person to confirm (its page is opened), or it failed. */
class InstallResult : BroadcastReceiver() {
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
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "安装失败"
                Toast.makeText(context, "没能更新：$message", Toast.LENGTH_LONG).show()
            }
        }
    }
}
