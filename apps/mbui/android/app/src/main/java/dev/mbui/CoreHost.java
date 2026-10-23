package dev.mbui;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import android.system.Os;

import com.facebook.soloader.nativeloader.NativeLoader;
import com.facebook.soloader.nativeloader.SystemDelegate;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyStore;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * The still.fail core's calls only the app does (src/host/android_core.c, on the core's thread; the engine is
 * apps/mbui/engine, prebuilt as libstillfail_hermes.so): {@code secure.*}, {@code listen.*}, {@code picked.*}, answered
 * here on a thread of their own and handed to the engine's {@code sf_engine_complete}, which android_core.c binds to
 * {@link #complete}. What the core says goes to C, not through here. One per running core.
 */
final class CoreHost {
    // The device as the core names it to the people who approve it (sfcore's `client.device`, as still.fail's Android
    // app tells it: maker and model), and its language (the locale's tag: the core's `lang` when none is chosen, the
    // app's words' until the core says: @sf.lang; a scripted run's own kept, e2e/android-flow.sh), in the environment
    // before the first core starts.
    static {
        try {
            Os.setenv("MBUI_DEVICE_MODEL", android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL, true);
            Os.setenv("MBUI_LOCALE", java.util.Locale.getDefault().toLanguageTag(), false);
        } catch (Exception e) {
            Host.log("device model: " + e);
        }
        // Hermes's Java side (String's normalize, Intl: AndroidUnicodeUtils, its Intl classes, fbjni's) loads its
        // libraries through NativeLoader: not set up, a formula's first letter ended the core (engine.cpp findJavaClasses).
        if (!NativeLoader.isInitialized()) NativeLoader.init(new SystemDelegate());
        // fbjni set up by its own JNI_OnLoad (the JavaVM those calls go through): only a library loaded by name has it
        // run, and libfbjni.so is otherwise only libhermes.so's dependency (its abort: "g_vm")
        System.loadLibrary("fbjni");
        // (the app's library, src/host/android_core.c in it: loaded already where the app runs, not where a push
        // started the process)
        System.loadLibrary("mbui");
    }

    /**
     * A push's core (Push.Service, on FCM's thread; android_core.c): the one running, else one started with no app's
     * client yet, which the app takes as its own if it starts meanwhile. True when one runs.
     */
    static native boolean startAlone(String cloud, boolean beta);

    /** The push handled: the core startAlone started stopped, unless the app has taken it. */
    static native void stopAlone();

    /** Whether a core runs in this process. */
    static native boolean running();

    /** Off the core's thread: the Keystore takes its time. */
    private static final ExecutorService calls = Executors.newSingleThreadExecutor();
    private static final ExecutorService listenCalls = Executors.newSingleThreadExecutor();
    /** A picked file's parts as they go up: a thread of their own (reading a video through takes a while). */
    private static final ExecutorService pickedCalls = Executors.newSingleThreadExecutor();

    private final String dataDir;
    /** The engine's handle once its start returned (a call can come before); 0 until then. */
    private long handle;
    private boolean closed;

    CoreHost(String dataDir) {
        this.dataDir = dataDir;
    }

    /** The engine's sf_engine_complete: {@code error} null when the call succeeded. */
    static native void complete(long handle, long id, String json, String error, byte[] bytes);

    synchronized void started(long h) {
        handle = h;
        notifyAll();
    }

    /** No answer reaches the engine after this (one being handed over finishes first). */
    void closing() {
        synchronized (this) {
            closed = true;
            notifyAll();
        }
        for (int lid : listens.keySet()) Loopback.close(lid);  // every listener of this core closes with it
    }

    void onApp(long id, String op, byte[] json, byte[] bytes) {
        if (op.startsWith("picked.")) {
            // a file picked too big to be read whole (mbui's Picks.Held), read a part at a time as it goes up
            // (`composer.add` with `blob: {hostFile}`; still.fail's Android app's PickedFiles.kt)
            pickedCalls.execute(() -> {
                try {
                    JSONObject a = new JSONObject(new String(json, StandardCharsets.UTF_8));
                    int file = a.getInt("file");
                    switch (op) {
                        case "picked.read":
                            answer(id, "{}", null, Picks.read(file, a.getLong("start"), a.getLong("end")));
                            break;
                        case "picked.hash":
                            answer(id, "{\"sha256\":\"" + Picks.hash(file) + "\"}", null, null);
                            break;
                        case "picked.release":
                            Picks.release(file);
                            answer(id, "{}", null, null);
                            break;
                        default:
                            answer(id, null, "unsupported", null);
                    }
                } catch (Throwable e) {
                    if (tracing()) Host.log("core app call " + op + " -> error " + errorText(e));
                    answer(id, null, op + ": " + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()), null);
                }
            });
            return;
        }
        if (op.startsWith("listen.")) {
            // A thread of their own, not the Keystore's: none of them waits (a listen.next is answered as a request
            // comes, from the listener's thread).
            listenCalls.execute(() -> {
                try {
                    listen(id, op, new JSONObject(new String(json, StandardCharsets.UTF_8)), bytes);
                } catch (Throwable e) {
                    if (tracing()) Host.log("core app call " + op + " -> error " + errorText(e));
                    answer(id, null, errorText(e), null);
                }
            });
            return;
        }
        calls.execute(() -> {
            String head = null, error = null;
            byte[] body = null;
            try {
                Answer a = op.startsWith("secure.") ? secure(op, new JSONObject(new String(json, StandardCharsets.UTF_8)), bytes)
                        : null;
                if (a == null) throw new Unsupported();
                head = a.json;
                body = a.bytes;
            } catch (Unsupported e) {
                error = "unsupported";
            } catch (SecureException | android.security.keystore.KeyPermanentlyInvalidatedException e) {
                error = errorText(e);
            } catch (Throwable e) {
                error = op + ": " + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName());
            }
            if (tracing()) Host.log("core app call " + op + " -> " + (error != null ? "error " + error
                    : head + (body != null ? " +" + body.length + " bytes" : "")));
            answer(id, head, error, body);
        });
    }

    /** The answer to call {@code id}, handed to the engine (once its start has returned; never after closing). */
    private void answer(long id, String head, String error, byte[] body) {
        synchronized (this) {
            while (handle == 0 && !closed) {
                try {
                    wait();
                } catch (InterruptedException e) {
                    return;
                }
            }
            if (closed) return;
            complete(handle, id, head, error, body);
        }
    }

    /** MB_CORE_TRACE=1 (the app's environment, `ENV=` of scripts/android.sh run): the app's calls said in the log. */
    static boolean tracing() {
        return "1".equals(Os.getenv("MB_CORE_TRACE"));
    }

    /**
     * An error as ember's app says it (SecureStore.errorText): a secure call's code (user_cancelled, no_device_lock…),
     * key_invalidated when the screen lock was taken off (what was sealed for the person cannot open), else the
     * exception's class and its message.
     */
    private static String errorText(Throwable e) {
        if (e instanceof SecureException s) return s.code;
        if (e instanceof android.security.keystore.KeyPermanentlyInvalidatedException) return "key_invalidated";
        return e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "");
    }

    /** A `secure.*` call that failed, `code` its whole message (client/core-ts host.ts `secureGet`). */
    private static final class SecureException extends Exception {
        final String code;

        SecureException(String code) {
            super(code);
            this.code = code;
        }
    }

    // ── listen.* (ember client/core-ts hosts/bridge.ts; ember's Loopback.kt, as apple_core.mm answers them) ──
    //   listen.open {port, host} → {id, port}, or the error (the port taken: "… Address already in use")
    //   listen.next {id} → {request, method, path, headers} + the body, or {end: true} once the listener is closed
    //   listen.respond {id, request, status, headers: [[name, value]]} + the body → {}
    //   listen.close {id} → {}
    // The listeners are Loopback's; what they take waits here for a listen.next. Each closes with this core.

    private static final class Listen {
        int lid;
        boolean ended;
        /** Requests no listen.next has taken yet. */
        final ArrayDeque<Loopback.Asked> requests = new ArrayDeque<>();
        /** listen.next calls waiting for a request. */
        final ArrayDeque<Long> waiting = new ArrayDeque<>();
    }

    private static final String END = "{\"end\":true}";
    private final Map<Integer, Listen> listens = new ConcurrentHashMap<>();

    private void listen(long id, String op, JSONObject a, byte[] bytes) throws Exception {
        if (tracing()) Host.log("core app call " + op + " " + a);
        int which = a.optInt("id", 0);
        switch (op) {
            case "listen.open": {
                if (!a.has("port") || !a.has("host")) throw new IllegalArgumentException("listen.open: port and host");
                Listen l = new Listen();
                int lid = Loopback.open(a.getString("host"), a.getInt("port"), r -> took(l, r));
                synchronized (l) {
                    l.lid = lid;
                }
                listens.put(lid, l);
                answer(id, "{\"id\":" + lid + ",\"port\":" + Loopback.port(lid) + "}", null, null);
                return;
            }
            case "listen.next": {
                Listen l = listens.get(which);
                Loopback.Asked r = null;
                if (l != null) {
                    synchronized (l) {
                        if (!l.ended) {
                            r = l.requests.poll();
                            if (r == null) {
                                l.waiting.add(id);
                                return;
                            }
                        }
                    }
                }
                if (r == null) answer(id, END, null, null);
                else answer(id, r.json(), null, r.body);
                return;
            }
            case "listen.respond": {
                List<String[]> headers = new ArrayList<>();
                JSONArray hs = a.optJSONArray("headers");
                for (int i = 0; hs != null && i < hs.length(); i++) {
                    JSONArray h = hs.optJSONArray(i);
                    if (h == null || h.length() < 2 || !(h.opt(0) instanceof String) || !(h.opt(1) instanceof String)) continue;
                    headers.add(new String[] {h.getString(0), h.getString(1)});
                }
                if (which != 0 && a.has("request"))
                    Loopback.respond(which, a.getLong("request"), a.optInt("status", 502), headers, bytes);
                answer(id, "{}", null, null);
                return;
            }
            case "listen.close":
                if (which != 0) Loopback.close(which);
                answer(id, "{}", null, null);
                return;
            default:
                answer(id, null, "unsupported", null);
        }
    }

    /** What a listener says, on its threads: a request (to a waiting listen.next, else kept), or its end. */
    private void took(Listen l, Loopback.Asked r) {
        long waiter;
        synchronized (l) {
            if (r == null) {
                l.ended = true;
                l.requests.clear();
                listens.remove(l.lid, l);
            } else if (l.ended) return;
        }
        if (r == null) {
            List<Long> ending;
            synchronized (l) {
                ending = new ArrayList<>(l.waiting);
                l.waiting.clear();
            }
            for (long w : ending) answer(w, END, null, null);
            return;
        }
        synchronized (l) {
            if (l.ended) return;
            Long w = l.waiting.poll();
            if (w == null) {
                l.requests.add(r);
                return;
            }
            waiter = w;
        }
        answer(waiter, r.json(), null, r.body);
    }

    private static final class Answer {
        final String json;
        final byte[] bytes;

        Answer(String json, byte[] bytes) {
            this.json = json;
            this.bytes = bytes;
        }
    }

    private static final class Unsupported extends Exception {}

    // ── secure.* (ember client/core-ts hosts/bridge.ts; ember apps/android core SecureStore.kt) ──
    //   secure.get {key, user, reason} → {} + the bytes, or {none: true}; secure.set {key, user} + the bytes → {};
    //   secure.delete {key} → {}; secure.ask {reason} → {} once the person said yes.
    // `user: false`: each value a file of <data>/secure (the key's UTF-8 in hex), sealed with AES-GCM under one key of
    // the Android Keystore (StrongBox where the phone has one), which never leaves it; the value's name is the cipher's
    // associated data, so one file can't stand in for another.
    // `user: true` (SecureStore.kt's): an RSA-2048 pair whose private half takes the person each time (biometrics or
    // the screen lock, BiometricPrompt over the activity, the core's `reason` in it); a value is sealed with a fresh
    // AES key wrapped to the public half, so keeping one asks nobody and only reading it does. It needs a screen lock,
    // and is gone for good once the screen lock is taken off (key_invalidated). Its files are <data>/secure-user, as
    // SecureStore.kt's: a version byte (1), 1, the wrapped key's length (2, big-endian), the wrapped key (RSA-OAEP,
    // SHA-256), the IV (12) and AES-GCM's output, its associated data naming the key and `user`.

    private static final String ALIAS = "dev.mbui.core.secure";
    private static final String PERSON = "dev.mbui.core.person";
    private static final byte VERSION = 1;
    private static final javax.crypto.spec.OAEPParameterSpec OAEP = new javax.crypto.spec.OAEPParameterSpec(
            "SHA-256", "MGF1", java.security.spec.MGF1ParameterSpec.SHA1, javax.crypto.spec.PSource.PSpecified.DEFAULT);

    private Answer secure(String op, JSONObject a, byte[] bytes) throws Exception {
        String reason = a.optString("reason", "");
        // asked by itself, before what the person should mean (turning the workspace lock off): no value, no key
        if (op.equals("secure.ask")) {
            if (!locked()) throw new SecureException("no_device_lock");
            ask(reason, null);
            return new Answer("{}", null);
        }
        String key = a.optString("key", "");
        if (key.isEmpty()) throw new IllegalArgumentException("no key");
        if (a.optBoolean("user")) return secureUser(op, key, reason, bytes);
        File file = new File(new File(dataDir, "secure"), hex(key.getBytes(StandardCharsets.UTF_8)));
        switch (op) {
            case "secure.get": {
                if (!file.exists()) {
                    // kept by still.fail's Android app before this one took its place (its signing key of the
                    // workspace's lock): opened with its key, kept again as this app keeps it
                    byte[] before = formerDevice(key);
                    if (before == null) return new Answer("{\"none\":true}", null);
                    secure("secure.set", a, before);
                    return new Answer("{}", before);
                }
                byte[] sealed = Files.readAllBytes(file.toPath());
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.DECRYPT_MODE, sealingKey(), new GCMParameterSpec(128, sealed, 0, 12));
                c.updateAAD(key.getBytes(StandardCharsets.UTF_8));
                return new Answer("{}", c.doFinal(sealed, 12, sealed.length - 12));
            }
            case "secure.set": {
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.ENCRYPT_MODE, sealingKey());
                c.updateAAD(key.getBytes(StandardCharsets.UTF_8));
                byte[] iv = c.getIV();
                byte[] out = c.doFinal(bytes != null ? bytes : new byte[0]);
                ByteArrayOutputStream all = new ByteArrayOutputStream();
                all.write(iv);
                all.write(out);
                keep(file, all.toByteArray());
                return new Answer("{}", null);
            }
            case "secure.delete":
                file.delete();
                new File(new File(dataDir, "secure-user"), hex(key.getBytes(StandardCharsets.UTF_8))).delete();
                former(key).delete();
                return new Answer("{}", null);
            default:
                throw new Unsupported();
        }
    }

    /** Written aside and renamed over: a crash leaves the old value or the new one, never half. */
    private static void keep(File file, byte[] content) throws Exception {
        File dir = file.getParentFile();
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IllegalStateException("no directory for it");
        File tmp = new File(dir, file.getName() + ".tmp");
        try (FileOutputStream f = new FileOutputStream(tmp)) {
            f.write(content);
            f.getFD().sync();
        }
        if (!tmp.renameTo(file)) throw new IllegalStateException("not written");
    }

    private static byte[] aad(String key) {
        return ("stillfail-sealed/1\u0000" + key + "\u00001").getBytes(StandardCharsets.UTF_8);
    }

    /** A value for the person (`user: true`): kept asking nobody, read once they say yes (SecureStore.kt get, set). */
    private Answer secureUser(String op, String key, String reason, byte[] bytes) throws Exception {
        File file = new File(new File(dataDir, "secure-user"), hex(key.getBytes(StandardCharsets.UTF_8)));
        switch (op) {
            case "secure.get": {
                // one kept by still.fail's Android app before this one took its place: the same file's form, sealed
                // to its own key for the person (read as it is: opening it takes the person anyway)
                String alias = PERSON;
                if (!file.exists()) {
                    File before = former(key);
                    if (!before.exists()) return new Answer("{\"none\":true}", null);
                    file = before;
                    alias = FORMER_PERSON;
                }
                byte[] blob = Files.readAllBytes(file.toPath());
                if (blob.length <= 2 || blob[0] != VERSION || blob[1] != 1) throw new IllegalArgumentException(key + ": not a sealed value");
                if (!locked()) throw new SecureException("no_device_lock");
                java.nio.ByteBuffer rest = java.nio.ByteBuffer.wrap(blob, 2, blob.length - 2);
                byte[] wrapped = new byte[rest.getShort() & 0xffff];
                rest.get(wrapped);
                byte[] iv = new byte[12];
                rest.get(iv);
                KeyStore ks = keystore();
                if (!(ks.getKey(alias, null) instanceof java.security.PrivateKey secret))
                    throw new android.security.keystore.KeyPermanentlyInvalidatedException("no key for what was sealed");
                Cipher unwrap = Cipher.getInstance("RSA/ECB/OAEPPadding");
                byte[] opened;
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    // the key takes the person for this one use: the prompt unlocks this cipher
                    unwrap.init(Cipher.DECRYPT_MODE, secret, OAEP);
                    android.hardware.biometrics.BiometricPrompt.CryptoObject crypto =
                            ask(reason, new android.hardware.biometrics.BiometricPrompt.CryptoObject(unwrap));
                    if (crypto == null) throw new SecureException("user_cancelled");
                    opened = (crypto.getCipher() != null ? crypto.getCipher() : unwrap).doFinal(wrapped);
                } else {
                    // Android 10: a key that takes the screen lock cannot be unlocked per use, only for a while after
                    // it was given (10 s): the person is asked first, then the key is used
                    ask(reason, null);
                    unwrap.init(Cipher.DECRYPT_MODE, secret, OAEP);
                    opened = unwrap.doFinal(wrapped);
                }
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.DECRYPT_MODE, new javax.crypto.spec.SecretKeySpec(opened, "AES"), new GCMParameterSpec(128, iv));
                c.updateAAD(aad(key));
                java.util.Arrays.fill(opened, (byte) 0);
                return new Answer("{}", c.doFinal(blob, rest.position(), rest.remaining()));
            }
            case "secure.set": {
                if (!locked()) throw new SecureException("no_device_lock");
                byte[] fresh = new byte[32];
                new java.security.SecureRandom().nextBytes(fresh);
                // the public half as a key of the platform's own provider: the Keystore's takes no part in it
                java.security.PublicKey half = java.security.KeyFactory.getInstance("RSA")
                        .generatePublic(new java.security.spec.X509EncodedKeySpec(personKey().getEncoded()));
                Cipher wrap = Cipher.getInstance("RSA/ECB/OAEPPadding");
                wrap.init(Cipher.ENCRYPT_MODE, half, OAEP);
                byte[] wrapped = wrap.doFinal(fresh);
                byte[] iv = new byte[12];
                new java.security.SecureRandom().nextBytes(iv);
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.ENCRYPT_MODE, new javax.crypto.spec.SecretKeySpec(fresh, "AES"), new GCMParameterSpec(128, iv));
                c.updateAAD(aad(key));
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                out.write(new byte[] {VERSION, 1});
                out.write(java.nio.ByteBuffer.allocate(2).putShort((short) wrapped.length).array());
                out.write(wrapped);
                out.write(iv);
                out.write(c.doFinal(bytes != null ? bytes : new byte[0]));
                java.util.Arrays.fill(fresh, (byte) 0);
                keep(file, out.toByteArray());
                return new Answer("{}", null);
            }
            case "secure.delete":
                file.delete();
                former(key).delete();
                return new Answer("{}", null);
            default:
                throw new Unsupported();
        }
    }

    // ── what still.fail's Android app kept, this app having taken its place (the same package, so its files and its
    // Keystore's keys): its sealed values (apps/android core SecureStore.kt), each a file of <files>/stillfail-sealed
    // named by its key (letters, digits, - and _ as they are, the rest %XX), a version byte (1), `user`, then for
    // `user: false` the IV (12) and AES-GCM's output under its key stillfail-sealed-device, its associated data
    // naming the key and `user`; for `user: true` this app's own form, under stillfail-sealed-person.

    private static final String FORMER_DEVICE = "stillfail-sealed-device";
    private static final String FORMER_PERSON = "stillfail-sealed-person";

    /** Where still.fail's Android app kept `key`'s value (SecureStore.kt fileName). */
    static File former(String key) {
        StringBuilder name = new StringBuilder();
        for (byte b : key.getBytes(StandardCharsets.UTF_8)) {
            char c = (char) (b & 0xff);
            if ((c < 128 && Character.isLetterOrDigit(c)) || c == '-' || c == '_') name.append(c);
            else name.append(String.format("%%%02X", b & 0xff));
        }
        return new File(new File(context().getFilesDir(), "stillfail-sealed"), name.toString());
    }

    /** still.fail's Android app's key for what it kept without asking (made here only by secureTest, where none is). */
    private static SecretKey formerDeviceKey() throws Exception {
        if (keystore().getKey(FORMER_DEVICE, null) instanceof SecretKey k) return k;
        KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(FORMER_DEVICE, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return g.generateKey();
    }

    /** A value still.fail's Android app kept without asking the person (`user: false`), opened; null where none is. */
    private static byte[] formerDevice(String key) throws Exception {
        File file = former(key);
        if (!file.exists()) return null;
        byte[] blob = Files.readAllBytes(file.toPath());
        if (blob.length < 2 + 12 + 16 || blob[0] != VERSION || blob[1] != 0) return null;
        if (!(keystore().getKey(FORMER_DEVICE, null) instanceof SecretKey k)) return null;
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE, k, new GCMParameterSpec(128, blob, 2, 12));
        c.updateAAD(("stillfail-sealed/1\u0000" + key + "\u00000").getBytes(StandardCharsets.UTF_8));
        return c.doFinal(blob, 14, blob.length - 14);
    }

    private static boolean locked() {
        android.app.KeyguardManager k = (android.app.KeyguardManager) context().getSystemService(android.content.Context.KEYGUARD_SERVICE);
        return k != null && k.isDeviceSecure();
    }

    private static KeyStore keystore() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        return ks;
    }

    /** A key made in the Keystore, in StrongBox where the phone has one (SecureStore.kt inStrongBox). */
    private interface Make<T> {
        T make(boolean strong) throws Exception;
    }

    private static <T> T inStrongBox(Make<T> make) throws Exception {
        if (context().getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
            try {
                return make.make(true);
            } catch (android.security.keystore.StrongBoxUnavailableException e) {
                // it says it has one, but not for this key: the Keystore's TEE then
            }
        }
        return make.make(false);
    }

    /** The person's key's public half: made the first time, and again when the one there can no longer be used. */
    private static synchronized java.security.PublicKey personKey() throws Exception {
        KeyStore ks = keystore();
        java.security.cert.Certificate cert = ks.getCertificate(PERSON);
        if (cert != null) {
            // taking the private half for a use says whether it still can be (the screen lock taken off ends it); it
            // does not ask the person yet
            try {
                Cipher.getInstance("RSA/ECB/OAEPPadding").init(Cipher.DECRYPT_MODE, (java.security.PrivateKey) ks.getKey(PERSON, null), OAEP);
                return cert.getPublicKey();
            } catch (android.security.keystore.KeyPermanentlyInvalidatedException e) {
                ks.deleteEntry(PERSON);
            } catch (android.security.keystore.UserNotAuthenticatedException e) {
                // Android 10's key, not given for a while: it is still there
                return cert.getPublicKey();
            }
        }
        return inStrongBox(strong -> {
            KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(PERSON, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                    .setUserAuthenticationRequired(true)
                    // whoever can unlock the phone can add a fingerprint: a new one does not end the key
                    .setInvalidatedByBiometricEnrollment(false)
                    .setIsStrongBoxBacked(strong);
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG | KeyProperties.AUTH_DEVICE_CREDENTIAL);
            } else {
                spec.setUserAuthenticationValidityDurationSeconds(10);
            }
            java.security.KeyPairGenerator g = java.security.KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore");
            g.initialize(spec.build());
            return g.generateKeyPair().getPublic();
        });
    }

    /**
     * Asks the person, over the activity in front (SecureStore.kt ask): biometrics or the screen lock, `reason` under
     * the app's name; `crypto` (Android 11 on) what the yes unlocks. Waits for the answer on this call's thread (one
     * secure call at a time, as SecureStore.kt's lock). Fails user_cancelled when they said no, no_device_lock when
     * there is nothing to ask with, not_in_front when no screen of the app is.
     */
    private static android.hardware.biometrics.BiometricPrompt.CryptoObject ask(
            String reason, android.hardware.biometrics.BiometricPrompt.CryptoObject crypto) throws Exception {
        MainActivity activity = Host.activity;
        if (activity == null || !Host.resumed) throw new SecureException("not_in_front");
        java.util.concurrent.CountDownLatch done = new java.util.concurrent.CountDownLatch(1);
        Object[] got = new Object[1];
        android.os.CancellationSignal cancel = new android.os.CancellationSignal();
        Host.main.post(() -> {
            android.hardware.biometrics.BiometricPrompt.Builder b = new android.hardware.biometrics.BiometricPrompt.Builder(activity)
                    .setTitle(activity.getApplicationInfo().loadLabel(activity.getPackageManager()));
            if (!reason.isEmpty()) b.setDescription(reason);
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                b.setAllowedAuthenticators(android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG
                        | android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL);
            } else {
                b.setDeviceCredentialAllowed(true);
            }
            android.hardware.biometrics.BiometricPrompt.AuthenticationCallback callback = new android.hardware.biometrics.BiometricPrompt.AuthenticationCallback() {
                @Override
                public void onAuthenticationSucceeded(android.hardware.biometrics.BiometricPrompt.AuthenticationResult result) {
                    got[0] = result.getCryptoObject() != null ? result.getCryptoObject() : Boolean.TRUE;
                    done.countDown();
                }

                @Override
                public void onAuthenticationError(int code, CharSequence message) {
                    String said;
                    switch (code) {
                        case android.hardware.biometrics.BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED:
                        case android.hardware.biometrics.BiometricPrompt.BIOMETRIC_ERROR_CANCELED:
                            said = "user_cancelled";
                            break;
                        case android.hardware.biometrics.BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL:
                        case android.hardware.biometrics.BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS:
                            said = "no_device_lock";
                            break;
                        default:
                            said = "biometric_error: " + message;
                    }
                    got[0] = new SecureException(said);
                    done.countDown();
                }
            };
            try {
                if (crypto != null) b.build().authenticate(crypto, cancel, activity.getMainExecutor(), callback);
                else b.build().authenticate(cancel, activity.getMainExecutor(), callback);
            } catch (RuntimeException e) {
                got[0] = new SecureException("biometric_error: " + e.getMessage());
                done.countDown();
            }
        });
        done.await();
        if (got[0] instanceof SecureException e) throw e;
        return got[0] instanceof android.hardware.biometrics.BiometricPrompt.CryptoObject c ? c : crypto;
    }

    /** The app's context (a push's core runs with no activity). */
    private static android.content.Context context() {
        return StillfailApp.app;
    }

    /**
     * MBUI_SECURE_TEST=1 (src/coredemo): secure.set, secure.get, secure.delete and secure.get again of a value of its
     * own, through the very code that answers the core's calls, on their thread; what each answered is said in the log
     * (SECURE_TEST …, never the value). From the UI's thread: returns at once.
     */
    static void secureTest() {
        String dir = dataDir();
        calls.execute(() -> {
            CoreHost h = new CoreHost(dir);
            String key = "mbui.secure-test";
            String args = "{\"key\":" + JSONObject.quote(key) + "}";
            byte[] value = new byte[48];
            new java.security.SecureRandom().nextBytes(value);
            boolean ok = true;
            try {
                long t0 = System.nanoTime();
                Answer set = h.secure("secure.set", new JSONObject(args), value);
                Host.log("SECURE_TEST secure.set " + set.json + " (" + value.length + " bytes)");
                Answer got = h.secure("secure.get", new JSONObject(args), null);
                boolean same = got.bytes != null && java.util.Arrays.equals(got.bytes, value);
                ok &= same;
                Host.log("SECURE_TEST secure.get " + got.json + " " + (got.bytes != null ? got.bytes.length : 0)
                        + " bytes, " + (same ? "the same" : "NOT the same"));
                File sealed = new File(new File(dir, "secure"), hex(key.getBytes(StandardCharsets.UTF_8)));
                boolean apart = sealed.exists() && !java.util.Arrays.equals(Files.readAllBytes(sealed.toPath()), value);
                ok &= apart;
                Host.log("SECURE_TEST on disk: " + (sealed.exists() ? sealed.length() + " bytes, " + (apart ? "sealed" : "NOT sealed") : "missing"));
                Answer del = h.secure("secure.delete", new JSONObject(args), null);
                Host.log("SECURE_TEST secure.delete " + del.json);
                Answer gone = h.secure("secure.get", new JSONObject(args), null);
                boolean none = "{\"none\":true}".equals(gone.json) && gone.bytes == null;
                ok &= none;
                Host.log("SECURE_TEST secure.get after delete " + gone.json);
                // one kept as still.fail's Android app kept it (SecureStore.kt set, user: false): read as it was, kept
                // again as this app keeps it, the former file gone with secure.delete
                String fkey = "mbui.secure-test.former";
                String fargs = "{\"key\":" + JSONObject.quote(fkey) + "}";
                File ffile = former(fkey);
                ffile.getParentFile().mkdirs();
                Cipher fc = Cipher.getInstance("AES/GCM/NoPadding");
                fc.init(Cipher.ENCRYPT_MODE, formerDeviceKey());
                fc.updateAAD(("stillfail-sealed/1\u0000" + fkey + "\u00000").getBytes(StandardCharsets.UTF_8));
                ByteArrayOutputStream fout = new ByteArrayOutputStream();
                fout.write(new byte[] {VERSION, 0});
                fout.write(fc.getIV());
                fout.write(fc.doFinal(value));
                keep(ffile, fout.toByteArray());
                Answer taken = h.secure("secure.get", new JSONObject(fargs), null);
                boolean same2 = taken.bytes != null && java.util.Arrays.equals(taken.bytes, value);
                File now = new File(new File(dir, "secure"), hex(fkey.getBytes(StandardCharsets.UTF_8)));
                ok &= same2 && now.exists();
                Host.log("SECURE_TEST former secure.get " + (same2 ? "the same" : "NOT the same") + ", " + (now.exists() ? "kept again" : "NOT kept again"));
                h.secure("secure.delete", new JSONObject(fargs), null);
                ok &= !ffile.exists() && !now.exists();
                Host.log("SECURE_TEST former secure.delete " + (!ffile.exists() && !now.exists() ? "both gone" : "NOT gone"));
                Host.log("SECURE_TEST " + (ok ? "ok" : "FAILED") + " in " + (System.nanoTime() - t0) / 1_000_000 + " ms (Android Keystore, AES-GCM)");
            } catch (Throwable e) {
                Host.log("SECURE_TEST FAILED: " + errorText(e));
            }
        });
    }

    private static synchronized SecretKey sealingKey() throws Exception {
        KeyStore ks = keystore();
        if (ks.getKey(ALIAS, null) instanceof SecretKey k) return k;
        return inStrongBox(strong -> {
            KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            g.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setIsStrongBoxBacked(strong)
                    .build());
            return g.generateKey();
        });
    }

    private static String hex(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x & 0xff));
        return s.toString();
    }

    // ── for android_core.c, on the UI's (GL) thread ──

    /**
     * A call only the app answers, at once, on the core's thread (android_core.c engine_app_sync, the engine's app_sync):
     * `text.collate {names}` the order people read the names in, the system's (ICU's collator in the device's language:
     * 中文 by pinyin, case and accents aside, digits by their value), each name's place in it, equal names one place:
     * {"value": [place, …]}. Null for anything else (the shell's answer), or a name that is no string (the core then
     * orders them by hand).
     */
    static String sync(String op, String json) {
        if (!"text.collate".equals(op)) return null;
        try {
            JSONArray names = new JSONObject(json).getJSONArray("names");
            int n = names.length();
            String[] s = new String[n];
            Integer[] order = new Integer[n];
            for (int i = 0; i < n; i++) {
                Object v = names.get(i);
                if (!(v instanceof String)) return null;
                s[i] = (String) v;
                order[i] = i;
            }
            android.icu.text.Collator c = android.icu.text.Collator.getInstance(android.icu.util.ULocale.getDefault());
            c.setStrength(android.icu.text.Collator.PRIMARY);
            if (c instanceof android.icu.text.RuleBasedCollator) ((android.icu.text.RuleBasedCollator) c).setNumericCollation(true);
            java.util.Arrays.sort(order, (x, y) -> c.compare(s[x], s[y]));
            int[] place = new int[n];
            for (int k = 0; k < n; k++) {
                place[order[k]] = k > 0 && c.compare(s[order[k - 1]], s[order[k]]) == 0 ? place[order[k - 1]] : k;
            }
            JSONArray out = new JSONArray();
            for (int p : place) out.put(p);
            return new JSONObject().put("value", out).toString();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Where the core keeps its files: the app's own files, never another app's. Where still.fail's Android app kept its
     * core's (this app having taken its place: the same package; apps/android StillFailCore.kt, <files>/stillfail-core,
     * the same core and shell, so the same files), they become this one's, as they are: its account, its chats, its
     * drafts, what it kept of the device.
     */
    static String dataDir() {
        File files = StillfailApp.app.getFilesDir();
        File d = new File(files, "core");
        File before = new File(files, "stillfail-core");
        if (!d.exists() && before.isDirectory()) {
            Host.log("core: still.fail's Android app's files taken " + (before.renameTo(d) ? "as they are" : "FAILED"));
        }
        d.mkdirs();
        return d.getAbsolutePath();
    }

    /** An asset of the APK (the core's bytecode), or null. */
    static byte[] asset(String name) {
        try (InputStream in = StillfailApp.app.getAssets().open(name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[1 << 16];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }
}
