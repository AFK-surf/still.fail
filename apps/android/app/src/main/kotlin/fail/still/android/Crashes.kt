// The app's crashes, to still.fail's PostHog project as `$exception` events, with the web's errors (docs/telemetry.md →
// Android). A crash in Kotlin is written down as it happens (its exception, which the system does not keep); at the next
// start the system's record of how the app's processes ended (ApplicationExitInfo) is read from where the last start
// left off, and each crash, native abort (Hermes, the core's JNI) or ANR goes out, with what the system kept of it: a
// native crash's tombstone, an ANR's thread dump. A build without PostHog's key (a local or dev one) sends nothing.
package fail.still.android

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

object Crashes {
    private const val DIR = "crashes"
    /** Where the last report left off in the system's record (its timestamp, ms). */
    private const val SINCE = "crashes.since"
    /** How far back the first start with this looks: the crashes from before it are what we want to see first. */
    private const val LOOK_BACK = 7L * 24 * 3600 * 1000
    /** At most this many each start, the newest. */
    private const val MOST = 20
    /** What goes up of one crash's trace, as the `trace` property. */
    const val LOGS = 60 * 1024
    /** A tombstone read at most this far (they carry memory dumps). */
    private const val TOMBSTONE = 4 * 1024 * 1024

    /** Keeps a Kotlin crash's exception in the app's files before the system's handler ends the process. */
    fun install(context: Context) {
        val before = Thread.getDefaultUncaughtExceptionHandler()
        if (before is Keeper) return
        Thread.setDefaultUncaughtExceptionHandler(Keeper(File(context.filesDir, DIR), before))
    }

    private class Keeper(val dir: File, val next: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(thread: Thread, e: Throwable) {
            try {
                dir.mkdirs()
                val kept = buildJsonObject {
                    put("thread", thread.name)
                    put("exceptions", exceptions(e))
                    put("stack", e.stackTraceToString().take(LOGS))
                }
                File(dir, "${System.currentTimeMillis()}.json").writeText(kept.toString())
            } catch (_: Throwable) {
            }
            next?.uncaughtException(thread, e)
        }
    }

    /** A throwable and its causes as PostHog's `$exception_list` (as posthog-android's ThrowableCoercer makes it). */
    fun exceptions(e: Throwable): JsonArray = buildJsonArray {
        val seen = mutableSetOf<Throwable>()
        var t: Throwable? = e
        while (t != null && seen.add(t) && seen.size <= 4) {
            val c: Throwable = t
            addJsonObject {
                val pkg = c.javaClass.`package`?.name
                put("type", if (pkg != null) c.javaClass.name.removePrefix("$pkg.") else c.javaClass.name)
                c.message?.takeIf { it.isNotEmpty() }?.let { put("value", it) }
                pkg?.let { put("module", it) }
                putJsonObject("mechanism") { put("handled", false); put("synthetic", false); put("type", if (c === e) "generic" else "chained") }
                // Bottom-up: the crash site last.
                val frames = c.stackTrace.reversed().takeLast(64)
                if (frames.isNotEmpty()) putJsonObject("stacktrace") {
                    put("type", "raw")
                    putJsonArray("frames") {
                        for (f in frames) addJsonObject {
                            put("module", f.className)
                            put("function", f.methodName)
                            put("platform", "java")
                            f.fileName?.let { put("filename", it) }
                            if (f.lineNumber >= 0) put("lineno", f.lineNumber)
                            put("in_app", f.className.startsWith("fail.still."))
                        }
                    }
                }
            }
            t = c.cause
        }
    }

    private class Report(val at: Long, val pid: Int, val exceptions: JsonArray, val fingerprint: String?, val trace: String?, val facts: JsonObject, val kept: File?)

    /** Where the core's restarts are told from: the account the last report went as (they come before one is known). */
    private const val ACCOUNT = "crashes.account"

    /** The core died and is started again (StillFailCore.onFailed): not a crash of the app, but what leads to one (its
     *  old engine's answers after it closed crashed the app, 2026-10), and the reason is the only trace of the core's
     *  own bug. Sent at once, as the web's CoreFailed is. */
    fun coreFailed(context: Context, reason: String) {
        if (BuildConfig.POSTHOG_KEY.isEmpty()) return
        val account = context.getSharedPreferences("stillfail", Context.MODE_PRIVATE).getString(ACCOUNT, null) ?: "android-anonymous"
        val at = System.currentTimeMillis()
        Thread {
            val r = Report(at, android.os.Process.myPid(), buildJsonArray {
                addJsonObject {
                    put("type", "CoreFailed")
                    put("value", reason.take(1000))
                    putJsonObject("mechanism") { put("handled", true); put("synthetic", false); put("type", "generic") }
                }
            }, null, null, buildJsonObject { put("reason", "core_failed") }, null)
            try {
                send(listOf(event(r, account, "error")))
            } catch (_: Exception) {
            }
        }.start()
    }

    /** Sends what crashed since the last start, as `account` (the signed-in account's id, the web's distinct id); what
     *  fails to go (offline) goes at the next start. */
    suspend fun report(context: Context, account: String) {
        if (BuildConfig.POSTHOG_KEY.isEmpty()) return
        val prefs = context.getSharedPreferences("stillfail", Context.MODE_PRIVATE)
        prefs.edit().putString(ACCOUNT, account).apply()
        withContext(Dispatchers.IO) {
            val reports = gather(context, prefs.getLong(SINCE, System.currentTimeMillis() - LOOK_BACK))
            if (reports.isEmpty()) return@withContext
            try {
                send(reports.map { event(it, account) })
            } catch (_: Exception) {
                return@withContext
            }
            prefs.edit().putLong(SINCE, reports.maxOf { it.at }).apply()
            reports.forEach { it.kept?.delete() }
        }
    }

    private fun event(r: Report, account: String, level: String = "fatal") = buildJsonObject {
        put("event", "\$exception")
        put("distinct_id", account)
        // The same crash sent again (its answer lost) is the same event: PostHog keeps one.
        put("uuid", UUID.nameUUIDFromBytes("android-$level-${r.at}-${r.pid}".toByteArray()).toString())
        put("timestamp", iso(r.at))
        putJsonObject("properties") {
            put("\$exception_list", r.exceptions)
            put("\$exception_level", level)
            r.fingerprint?.let { put("\$exception_fingerprint", it) }
            r.trace?.let { put("trace", it) }
            put("release", BuildConfig.VERSION_NAME)
            put("app", "android")
            put("beta", BuildConfig.BETA)
            put("\$app_version", BuildConfig.VERSION_NAME)
            put("\$os", "Android")
            put("\$os_version", Build.VERSION.RELEASE)
            put("\$device_manufacturer", Build.MANUFACTURER)
            put("\$device_model", Build.MODEL)
            put("\$lib", "stillfail-android")
            for ((k, v) in r.facts) put(k, v)
        }
    }

    private fun send(batch: List<JsonObject>) {
        val body = buildJsonObject { put("api_key", BuildConfig.POSTHOG_KEY); put("batch", JsonArray(batch)) }.toString().toByteArray()
        val c = URL("${BuildConfig.POSTHOG_HOST.trimEnd('/')}/batch/").openConnection() as HttpURLConnection
        try {
            c.requestMethod = "POST"
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            c.doOutput = true
            c.setRequestProperty("content-type", "application/json")
            c.outputStream.use { it.write(body) }
            val status = c.responseCode
            if (status !in 200..299) throw java.io.IOException("posthog answered $status")
        } finally {
            c.disconnect()
        }
    }

    private fun gather(context: Context, since: Long): List<Report> {
        val dir = File(context.filesDir, DIR)
        val kept = (dir.listFiles() ?: emptyArray()).mapNotNull { f -> f.name.removeSuffix(".json").toLongOrNull()?.let { it to f } }.toMutableList()
        // The system keeps how processes ended from Android 11 on; before it, only the exceptions written down here.
        val made = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ended(context, since, kept) else mutableListOf()
        // An exception kept with no end recorded (the record cleared, or older than it goes back): on its own.
        for ((at, file) in kept) if (at > since) made += javaOnly(at, file) else file.delete()
        return made.sortedBy { it.at }.takeLast(MOST)
    }

    /** The crashes and ANRs in the system's record since `since`, each with its exception kept here (taken out of `kept`). */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun ended(context: Context, since: Long, kept: MutableList<Pair<Long, File>>): MutableList<Report> {
        val exits = try {
            context.getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(context.packageName, 0, 0)
        } catch (_: Exception) {
            emptyList()
        }
        val wanted = setOf(ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE, ApplicationExitInfo.REASON_ANR)
        return exits.filter { it.timestamp > since && it.reason in wanted }.map { exit ->
            // The exception written down as it crashed: the file made just before the system recorded the end.
            val file = if (exit.reason == ApplicationExitInfo.REASON_CRASH) kept.filter { it.first in exit.timestamp - 10_000..exit.timestamp + 1_000 }.maxByOrNull { it.first } else null
            if (file != null) kept.remove(file)
            of(exit, file?.second)
        }.toMutableList()
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun of(exit: ApplicationExitInfo, kept: File?): Report {
        val trace = try {
            exit.traceInputStream?.use { if (exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) Tombstone.text(readAtMost(it, TOMBSTONE)) else it.readBytes().decodeToString().take(LOGS) }
        } catch (_: Exception) {
            null
        }
        val facts = buildJsonObject {
            put("reason", when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH -> "crash"
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
                else -> "anr"
            })
            put("exit_status", exit.status)
            put("exit_description", exit.description)
            put("process", exit.processName)
            put("importance", exit.importance)
            put("pss_kb", exit.pss)
            put("rss_kb", exit.rss)
        }
        val description = exit.description ?: ""
        return when (exit.reason) {
            ApplicationExitInfo.REASON_CRASH -> {
                val k = kept?.let(::read)
                Report(exit.timestamp, exit.pid, k?.exceptions ?: one("Crash", description, "generic"), null, k?.stack ?: trace, facts, kept)
            }
            ApplicationExitInfo.REASON_CRASH_NATIVE -> {
                val signal = trace?.let(Tombstone::signal) ?: "NativeCrash"
                val frames = trace?.let(Tombstone::frames).orEmpty()
                Report(exit.timestamp, exit.pid, one(signal, trace?.let(Tombstone::headline) ?: description, "signalhandler"), fingerprint(signal, frames), trace, facts, null)
            }
            else -> Report(exit.timestamp, exit.pid, one("ANR", description, "anr"), fingerprint("ANR", trace?.let(::mainFrames).orEmpty()), trace, facts, null)
        }
    }

    private fun javaOnly(at: Long, file: File): Report {
        val k = read(file)
        return Report(at, 0, k?.exceptions ?: one("Crash", "", "generic"), null, k?.stack, buildJsonObject { put("reason", "crash") }, file)
    }

    private class Kept(val exceptions: JsonArray, val stack: String?)

    private fun read(file: File): Kept? = try {
        val v = Json.parseToJsonElement(file.readText()).jsonObject
        Kept(v["exceptions"] as JsonArray, (v["stack"] as? kotlinx.serialization.json.JsonPrimitive)?.content)
    } catch (_: Exception) {
        null
    }

    private fun one(type: String, value: String, mechanism: String) = buildJsonArray {
        addJsonObject {
            put("type", type)
            if (value.isNotEmpty()) put("value", value)
            putJsonObject("mechanism") { put("handled", false); put("synthetic", false); put("type", mechanism) }
        }
    }

    /** What makes two native crashes or ANRs the same issue (no frames PostHog reads for them): where they happened. */
    private fun fingerprint(kind: String, frames: List<String>): String? =
        if (frames.isEmpty()) null else "android:$kind:" + frames.take(6).joinToString("|")

    /** The main thread's top frames in an ANR's dump. */
    fun mainFrames(dump: String): List<String> =
        dump.lineSequence().dropWhile { !it.startsWith("\"main\"") }.drop(1).takeWhile { it.isNotBlank() }
            .map { it.trim() }.filter { it.startsWith("at ") }.map { it.removePrefix("at ").substringBefore('(') }.toList()

    private fun iso(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(ms))

    private fun readAtMost(input: InputStream, most: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(64 * 1024)
        while (out.size() < most) {
            val n = input.read(buf, 0, minOf(buf.size, most - out.size()))
            if (n < 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }
}
