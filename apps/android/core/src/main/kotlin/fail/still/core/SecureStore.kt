package fail.still.core

import android.app.Activity
import android.app.Application
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.ByteArrayOutputStream
import java.io.File
import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A `secure.*` call that failed, `code` its whole message (client/core-ts host.ts `secureGet`: `user_cancelled`, …). */
internal class SecureException(val code: String) : Exception(code)

/**
 * What the core keeps sealed (client/core-ts host.ts `secureGet`; docs/vault.md, "设备上的钥匙"): each value a file of
 * its own in `dir` (the app's files, never backed up), sealed by a key in the Android Keystore (StrongBox where the
 * phone has it). Two keys:
 *  - `user: false`: AES-256-GCM in the Keystore, used without asking (the lock's signing key).
 *  - `user: true`: an RSA-2048 pair whose private half takes the person each time (biometrics or the screen lock,
 *    BiometricPrompt over the activity in front, the core's `reason` in it); a value is sealed with a fresh AES key
 *    wrapped to the public half, so keeping one asks nobody and only reading it does. It needs a screen lock, and is
 *    gone for good if the screen lock is taken off (`key_invalidated`).
 *
 * A file: a version byte (1), a byte for `user`, then for `user: false` the IV (12) and AES-GCM's output; for
 * `user: true` the wrapped key's length (2, big-endian), the wrapped key (RSA-OAEP, SHA-256), the IV and AES-GCM's
 * output. The additional data names the key and `user`, so a file copied to another key, or its `user` byte
 * changed, does not open.
 */
internal class SecureStore(private val context: Context, private val dir: File) {
    companion object {
        private const val VERSION: Byte = 1
        private const val DEVICE = "stillfail-sealed-device"
        private const val PERSON = "stillfail-sealed-person"
        private val OAEP = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT)

        @Volatile private var shared: SecureStore? = null

        /** The app's (one per process). */
        fun of(context: Context): SecureStore = shared ?: synchronized(this) {
            shared ?: SecureStore(context.applicationContext, File(context.applicationContext.filesDir, "stillfail-sealed")).also { shared = it }
        }

        /** A failure as the core reads it: a code, or what went wrong. */
        fun errorText(e: Throwable): String = when (e) {
            is SecureException -> e.code
            // The screen lock was taken off (or the Keystore lost the key): what it sealed with `user` cannot open.
            is KeyPermanentlyInvalidatedException -> "key_invalidated"
            else -> "${e.javaClass.simpleName}: ${e.message ?: ""}"
        }

        /** A key as a file name: letters, digits, `-` and `_` as they are, the rest `%XX`. */
        fun fileName(key: String): String = buildString {
            for (b in key.toByteArray(Charsets.UTF_8)) {
                val c = (b.toInt() and 0xff).toChar()
                if (c.isLetterOrDigit() && c.code < 128 || c == '-' || c == '_') append(c) else append("%%%02X".format(b.toInt() and 0xff))
            }
        }

        private fun aad(key: String, user: Boolean) = "stillfail-sealed/1\u0000$key\u0000${if (user) 1 else 0}".toByteArray(Charsets.UTF_8)
    }

    /** One call at a time: keys made once, one prompt at a time. */
    private val busy = Mutex()
    private val keystore: KeyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }

    /** A `secure.*` call: the answer's JSON and bytes. */
    suspend fun answer(op: String, json: String, bytes: ByteArray?): Pair<String, ByteArray?> {
        val a = Json.parseToJsonElement(json).jsonObject
        val key = a["key"]?.jsonPrimitive?.contentOrNull ?: throw IllegalArgumentException("no key")
        val user = a["user"]?.jsonPrimitive?.booleanOrNull ?: false
        return busy.withLock {
            when (op) {
                "secure.get" -> get(key, user, a["reason"]?.jsonPrimitive?.contentOrNull ?: "")?.let { "{}" to it } ?: ("{\"none\":true}" to null)
                "secure.set" -> withContext(Dispatchers.IO) { set(key, bytes ?: ByteArray(0), user) }.let { "{}" to null }
                "secure.delete" -> withContext(Dispatchers.IO) { File(dir, fileName(key)).delete() }.let { "{}" to null }
                else -> throw IllegalArgumentException("no such call: $op")
            }
        }
    }

    private fun locked(): Boolean = (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure

    suspend fun get(key: String, user: Boolean, reason: String): ByteArray? {
        val blob = withContext(Dispatchers.IO) { File(dir, fileName(key)).takeIf { it.exists() }?.readBytes() } ?: return null
        require(blob.size > 2 && blob[0] == VERSION) { "$key: not a sealed value" }
        val kept = blob[1].toInt() == 1
        require(kept == user) { "$key: kept with user: $kept, asked with user: $user" }
        val rest = ByteBuffer.wrap(blob, 2, blob.size - 2)
        if (!user) {
            val iv = ByteArray(12).also { rest.get(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, deviceKey(), GCMParameterSpec(128, iv))
            cipher.updateAAD(aad(key, false))
            return cipher.doFinal(blob, rest.position(), rest.remaining())
        }
        if (!locked()) throw SecureException("no_device_lock")
        val wrapped = ByteArray(rest.short.toInt() and 0xffff).also { rest.get(it) }
        val iv = ByteArray(12).also { rest.get(it) }
        val secret = keystore.getKey(PERSON, null) as? PrivateKey ?: throw KeyPermanentlyInvalidatedException("no key for what was sealed")
        val unwrap = Cipher.getInstance("RSA/ECB/OAEPPadding")
        val opened: ByteArray = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // The key takes the person for this one use: the prompt unlocks this cipher.
            unwrap.init(Cipher.DECRYPT_MODE, secret, OAEP)
            val crypto = ask(reason, BiometricPrompt.CryptoObject(unwrap)) ?: throw SecureException("user_cancelled")
            (crypto.cipher ?: unwrap).doFinal(wrapped)
        } else {
            // Android 10: a key that takes the screen lock cannot be unlocked per use, only for a while after it was
            // given (10 s): the person is asked first, then the key is used.
            ask(reason, null)
            unwrap.init(Cipher.DECRYPT_MODE, secret, OAEP)
            unwrap.doFinal(wrapped)
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(opened, "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(aad(key, true))
        return cipher.doFinal(blob, rest.position(), rest.remaining())
    }

    private fun set(key: String, value: ByteArray, user: Boolean) {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(VERSION, if (user) 1 else 0))
        if (!user) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, deviceKey())
            cipher.updateAAD(aad(key, false))
            val sealed = cipher.doFinal(value)
            out.write(cipher.iv)
            out.write(sealed)
        } else {
            if (!locked()) throw SecureException("no_device_lock")
            val fresh = ByteArray(32).also { SecureRandom().nextBytes(it) }
            // The public half as a key of the platform's own provider: the Keystore's takes no part in it.
            val half = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(personKey().encoded))
            val wrap = Cipher.getInstance("RSA/ECB/OAEPPadding")
            wrap.init(Cipher.ENCRYPT_MODE, half, OAEP)
            val wrapped = wrap.doFinal(fresh)
            val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(fresh, "AES"), GCMParameterSpec(128, iv))
            cipher.updateAAD(aad(key, true))
            out.write(ByteBuffer.allocate(2).putShort(wrapped.size.toShort()).array())
            out.write(wrapped)
            out.write(iv)
            out.write(cipher.doFinal(value))
            fresh.fill(0)
        }
        // Written aside and renamed over: a crash leaves the old value or the new one, never half.
        dir.mkdirs()
        val path = File(dir, fileName(key))
        val partial = File(dir, "${path.name}.partial")
        partial.outputStream().use { it.write(out.toByteArray()); it.fd.sync() }
        if (!partial.renameTo(path)) throw java.io.IOException("$key: could not be kept")
    }

    /** Makes a key in the Keystore, in StrongBox where the phone has one. */
    private fun <T> inStrongBox(make: (strong: Boolean) -> T): T {
        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
            try {
                return make(true)
            } catch (_: StrongBoxUnavailableException) {
                // It says it has one, but not for this key: the Keystore's TEE then.
            }
        }
        return make(false)
    }

    private fun deviceKey(): SecretKey {
        (keystore.getKey(DEVICE, null) as? SecretKey)?.let { return it }
        return inStrongBox { strong ->
            val spec = KeyGenParameterSpec.Builder(DEVICE, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setIsStrongBoxBacked(strong)
                .build()
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(spec) }.generateKey()
        }
    }

    /** The person's key's public half: made the first time, and again when the one there can no longer be used. */
    private fun personKey(): java.security.PublicKey {
        val had = keystore.getCertificate(PERSON)?.publicKey
        if (had != null) {
            // Taking the private half for a use says whether it still can be (the screen lock taken off ends it);
            // it does not ask the person yet.
            try {
                Cipher.getInstance("RSA/ECB/OAEPPadding").init(Cipher.DECRYPT_MODE, keystore.getKey(PERSON, null) as PrivateKey, OAEP)
                return had
            } catch (_: KeyPermanentlyInvalidatedException) {
                keystore.deleteEntry(PERSON)
            } catch (_: android.security.keystore.UserNotAuthenticatedException) {
                // Android 10's key, not given for a while: it is still there.
                return had
            }
        }
        return inStrongBox { strong ->
            val spec = KeyGenParameterSpec.Builder(PERSON, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                .setUserAuthenticationRequired(true)
                // Whoever can unlock the phone can add a fingerprint: a new one does not end the key.
                .setInvalidatedByBiometricEnrollment(false)
                .setIsStrongBoxBacked(strong)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)
                    } else {
                        @Suppress("DEPRECATION") setUserAuthenticationValidityDurationSeconds(10)
                    }
                }
                .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore").apply { initialize(spec) }.generateKeyPair().public
        }
    }

    /**
     * Asks the person, over the activity in front: biometrics or the screen lock, `reason` under the app's name.
     * `crypto` (Android 11 on): what the yes unlocks. Fails `user_cancelled` when they said no, `no_device_lock` when
     * there is nothing to ask with, `not_in_front` when no screen of the app is.
     */
    private suspend fun ask(reason: String, crypto: BiometricPrompt.CryptoObject?): BiometricPrompt.CryptoObject? = withContext(Dispatchers.Main) {
        val activity = Foreground.activity ?: throw SecureException("not_in_front")
        suspendCancellableCoroutine { going ->
            val cancel = CancellationSignal()
            going.invokeOnCancellation { cancel.cancel() }
            val builder = BiometricPrompt.Builder(activity).setTitle(activity.applicationInfo.loadLabel(activity.packageManager))
            if (reason.isNotEmpty()) builder.setDescription(reason)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            } else {
                @Suppress("DEPRECATION") builder.setDeviceCredentialAllowed(true)
            }
            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (going.isActive) going.resume(result.cryptoObject)
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    val said = when (code) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED, BiometricPrompt.BIOMETRIC_ERROR_CANCELED -> "user_cancelled"
                        BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL, BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS -> "no_device_lock"
                        else -> "biometric_error: $message"
                    }
                    if (going.isActive) going.resumeWithException(SecureException(said))
                }
            }
            if (crypto != null) builder.build().authenticate(crypto, cancel, activity.mainExecutor, callback)
            else builder.build().authenticate(cancel, activity.mainExecutor, callback)
        }
    }
}

/**
 * The app's activity in front, for what has to be asked over one (SecureStore's prompt). Watched from the core's start
 * (StillFailCore.start, before the first activity is on screen); a weak reference, so it keeps no activity alive.
 */
internal object Foreground : Application.ActivityLifecycleCallbacks {
    @Volatile private var front: WeakReference<Activity>? = null
    private var watching = false

    val activity: Activity? get() = front?.get()?.takeIf { !it.isFinishing && !it.isDestroyed }

    fun watch(context: Context) {
        val app = context.applicationContext as? Application ?: return
        synchronized(this) {
            if (watching) return
            watching = true
        }
        app.registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) {
        front = WeakReference(activity)
    }

    override fun onActivityPaused(activity: Activity) {
        if (front?.get() === activity) front = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
