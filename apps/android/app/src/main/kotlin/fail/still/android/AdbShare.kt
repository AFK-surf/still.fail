// This phone's adb, lent to a station's agents (docs/adb-share.md): Wireless debugging's ports found on the phone
// (DNS-SD) and given to the core (`adb.share`), which offers them to the station and carries what its agents' adb sends
// (client/core-ts/src/adb.ts). A foreground service holds the app up meanwhile and says so, with 停止 and, while the pairing
// dialog is open, a field for its code: the dialog closes if Settings is left, so the code is typed here.
package fail.still.android

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import fail.still.android.data.AdbShareView
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.errorText
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import fail.still.android.ui.t
import java.net.InetAddress
import java.net.NetworkInterface
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object AdbShare {
    const val STATION = "station"
    const val NAME = "name"
    internal const val CODE = "code"
    internal const val START = "fail.still.android.adb.START"
    internal const val STOP = "fail.still.android.adb.STOP"
    internal const val PAIR = "fail.still.android.adb.PAIR"
    private const val CHANNEL = "adb"
    internal const val ID = 7
    /** `Settings.Global.ADB_WIFI_ENABLED`, which the SDK hides. */
    private const val WIRELESS = "adb_wifi_enabled"

    /** Wireless debugging is Android 11's. */
    val supported get() = Build.VERSION.SDK_INT >= 30

    /** Lends the phone to `station`'s agents (`name`, for the notification); another station's in place of one before. */
    fun start(context: Context, station: String, name: String) {
        context.startForegroundService(Intent(context, AdbShareService::class.java).setAction(START).putExtra(STATION, station).putExtra(NAME, name))
    }

    fun developerOptions(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
    fun wirelessOn(context: Context) = Settings.Global.getInt(context.contentResolver, WIRELESS, 0) == 1
    /** Whether the app may turn Wireless debugging on itself: the station's adb granted it (`adb.grant`). */
    fun canSwitch(context: Context) = context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
    fun switchOn(context: Context): Boolean = canSwitch(context) && runCatching { Settings.Global.putInt(context.contentResolver, WIRELESS, 1) }.getOrDefault(false)
    fun wirelessUri() = Settings.Global.getUriFor(WIRELESS)

    /** Wireless debugging needs Wi-Fi: Android turns it off without. */
    fun onWifi(context: Context): Boolean {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return false
        return connectivity.getNetworkCapabilities(connectivity.activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    /** Developer options, at Wireless debugging (its row lit up), where it is turned on and paired. */
    fun openWireless(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).putExtra(":settings:fragment_args_key", "toggle_adb_wireless").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure { context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    internal fun notification(context: Context, view: AdbShareView?, name: String, said: String?): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, t("android-misc.adb.title"), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(context, 1, Intent(context, AdbShareService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
        val text = said ?: line(view)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFE5704A.toInt())
            .setContentTitle(t("android-misc.adb.notify.title", "name" to name))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, t("android-misc.adb.stop"), stop).build())
        // The pairing dialog is open (its port is announced): its code is typed here, Settings staying where it is.
        if (view?.pairPort != null && view.adb != "connected") {
            val pair = PendingIntent.getService(context, 2, Intent(context, AdbShareService::class.java).setAction(PAIR), PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val input = RemoteInput.Builder(CODE).setLabel(t("android-misc.adb.code")).build()
            builder.addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, t("android-misc.adb.enterCode"), pair).addRemoteInput(input).build())
        }
        return builder.build()
    }

    /** How it stands, in a line. */
    fun line(view: AdbShareView?): String = when {
        view == null || view.phase == "connecting" -> view?.message ?: t("android-misc.adb.connecting")
        view.adb == "connected" -> view.until?.let { t("android-misc.adb.connected.left", "n" to minutesLeft(it)) } ?: t("android-misc.adb.connected")
        view.adb == "unpaired" -> if (view.pairPort != null) t("android-misc.adb.typeCode") else t("android-misc.adb.notPaired")
        view.adb == "off" -> t("android-misc.adb.off")
        else -> view.message ?: t("android-misc.adb.attaching")
    }

    fun minutesLeft(until: Long) = ((until - System.currentTimeMillis()) / 60_000).coerceAtLeast(0)
}

/**
 * Holds the app up while the phone is lent (a foreground service): finds Wireless debugging's ports and tells the core
 * each time they change, says in its notification how it stands, takes the pairing code typed there, and ends when the
 * core's `adbShare` says the phone is lent no longer (stopped, its hour up, the station too old).
 */
class AdbShareService : Service() {
    private val scope = MainScope()
    private var job: Job? = null
    private var ports: AdbPorts? = null
    private var name = ""
    private var view: AdbShareView? = null
    /** What the notification says in place of how it stands: a pairing under way, why one failed; until adb holds the phone. */
    private var note: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            AdbShare.START -> {
                val station = intent.getStringExtra(AdbShare.STATION) ?: return START_NOT_STICKY
                name = intent.getStringExtra(AdbShare.NAME) ?: "station"
                val shown = AdbShare.notification(this, null, name, null)
                if (Build.VERSION.SDK_INT >= 34) startForeground(AdbShare.ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                else startForeground(AdbShare.ID, shown)
                begin(station)
            }
            AdbShare.STOP -> scope.launch {
                try { core().call("adb.stop") } catch (_: CoreException) { stopSelf() }
            }
            AdbShare.PAIR -> {
                val code = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(AdbShare.CODE)?.toString().orEmpty()
                note = t("android-misc.adb.pairing")
                say()
                scope.launch {
                    note = try {
                        core().call("adb.pair", buildJsonObject { put("code", code) })
                        null
                    } catch (e: CoreException) {
                        t("android-misc.adb.pairFailed", "error" to errorText(e))
                    }
                    say()
                }
            }
        }
        return START_NOT_STICKY
    }

    private suspend fun core() = StillFailCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN, BuildConfig.BETA)

    /** The notification again, as it stands now (or as `note` says). */
    private fun say() {
        getSystemService(NotificationManager::class.java).notify(AdbShare.ID, AdbShare.notification(this, view, name, note))
    }

    private fun begin(station: String) {
        job?.cancel()
        ports?.stop()
        val found = AdbPorts(this).also { ports = it }
        job = scope.launch {
            val core = core()
            // Granted before (`adb.grant`): on by itself, as Android allows only on Wi-Fi.
            if (!AdbShare.wirelessOn(this@AdbShareService) && AdbShare.onWifi(this@AdbShareService)) AdbShare.switchOn(this@AdbShareService)
            found.start()
            launch {
                found.ports.collect { (connect, pair) ->
                    try {
                        core.call("adb.share", buildJsonObject {
                            put("station", station)
                            connect?.let { put("connect", it) }
                            pair?.let { put("pair", it) }
                            put("device", Build.MODEL)
                            put("android", Build.VERSION.RELEASE)
                            put("package", packageName)
                        })
                    } catch (e: CoreException) {
                        note = t("android-misc.adb.shareFailed", "error" to errorText(e))
                        say()
                        stopSelf()
                    }
                }
            }
            // 还剩 N 分钟, as the minutes go.
            launch { while (true) { delay(60_000); say() } }
            // Until the core says it is lent no longer (it says so first, before the offer above is made).
            var lent = false
            core.topic(Topics.adbShare).collect { state ->
                val value = state.value?.takeIf { it !is JsonNull }?.let { runCatching { decode(AdbShareView.serializer(), it) }.getOrNull() } ?: return@collect
                view = value
                if (value.adb == "connected") note = null
                if (value.sharing && value.station == station) lent = true
                if (lent && (!value.sharing || value.station != station)) {
                    if (value.station == null) stopSelf()
                    return@collect
                }
                say()
            }
        }
    }

    override fun onDestroy() {
        ports?.stop()
        scope.cancel()
        // Gone with the service, whatever ended it.
        MainScope().launch { try { core().call("adb.stop") } catch (_: CoreException) {} }
        super.onDestroy()
    }
}

/**
 * Wireless debugging's ports on this phone, as it announces them (DNS-SD): adb's (`_adb-tls-connect._tcp`) while it is
 * on and, while the pairing dialog is open, the pairing one (`_adb-tls-pairing._tcp`). Only this phone's own: others'
 * on the same Wi-Fi are announced too.
 */
class AdbPorts(context: Context) {
    data class Found(val connect: Int?, val pair: Int?)

    val ports = MutableStateFlow(Found(null, null))
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    /** The older resolver takes one at a time. */
    private var resolving = false
    private val queue = ArrayDeque<Pair<NsdServiceInfo, (Int) -> Unit>>()

    fun start() {
        discover("_adb-tls-connect._tcp") { port -> ports.update { it.copy(connect = port) } }
        discover("_adb-tls-pairing._tcp") { port -> ports.update { it.copy(pair = port) } }
    }

    fun stop() {
        listeners.forEach { runCatching { nsd.stopServiceDiscovery(it) } }
        listeners.clear()
    }

    private fun discover(type: String, set: (Int?) -> Unit) {
        // By the service's name: one goes as Wireless debugging (or the dialog) closes, another comes as it opens again.
        val found = LinkedHashMap<String, Int>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                resolve(info) { port -> main.post { found[info.serviceName] = port; set(found.values.lastOrNull()) } }
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                main.post { found.remove(info.serviceName); set(found.values.lastOrNull()) }
            }
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) {}
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        }
        listeners += listener
        runCatching { nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
    }

    private fun resolve(info: NsdServiceInfo, done: (Int) -> Unit) {
        if (Build.VERSION.SDK_INT >= 34) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceUpdated(resolved: NsdServiceInfo) {
                    if (mine(resolved.hostAddresses)) done(resolved.port)
                    runCatching { nsd.unregisterServiceInfoCallback(this) }
                }
                override fun onServiceInfoCallbackRegistrationFailed(code: Int) {}
                override fun onServiceLost() {}
                override fun onServiceInfoCallbackUnregistered() {}
            }
            runCatching { nsd.registerServiceInfoCallback(info, { main.post(it) }, callback) }
            return
        }
        main.post {
            queue.addLast(info to done)
            next()
        }
    }

    @Suppress("DEPRECATION")
    private fun next() {
        if (resolving) return
        val (info, done) = queue.removeFirstOrNull() ?: return
        resolving = true
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(resolved: NsdServiceInfo) {
                if (mine(listOfNotNull(resolved.host))) done(resolved.port)
                main.post { resolving = false; next() }
            }
            override fun onResolveFailed(failed: NsdServiceInfo, code: Int) {
                main.post { resolving = false; next() }
            }
        })
    }

    /** Whether an announced host is this phone. */
    private fun mine(hosts: List<InetAddress>): Boolean {
        val own = runCatching { NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() } }.getOrDefault(emptyList())
        return hosts.any { it in own }
    }
}
