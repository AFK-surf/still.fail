package dev.mbui;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import android.system.Os;

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
 * The still.fail core's listener (src/host/android_core.c): what ember's engine (its engine.cpp, prebuilt as
 * libstillfail_hermes.so) calls back with on the core's thread. What the core says goes straight back to C
 * ({@link #onBytes}, {@link #onFrame}); the calls only the app does ({@code secure.*}, {@code listen.*}) are answered
 * here on a thread of their own and handed to the engine's {@code complete}, which android_core.c binds to
 * {@link #complete}. One per running core.
 */
final class CoreHost {
    // The device as the core names it to the people who approve it (sfcore's `client.device`, as still.fail's Android
    // app tells it: maker and model), in the environment before the first core starts.
    static {
        try {
            Os.setenv("MBUI_DEVICE_MODEL", android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL, true);
        } catch (Exception e) {
            Host.log("device model: " + e);
        }
    }

    /** Off the core's thread: the Keystore takes its time. */
    private static final ExecutorService calls = Executors.newSingleThreadExecutor();
    private static final ExecutorService listenCalls = Executors.newSingleThreadExecutor();

    private final String dataDir;
    /** The engine's handle once its start returned (a call can come before); 0 until then. */
    private long handle;
    private boolean closed;

    CoreHost(String dataDir) {
        this.dataDir = dataDir;
    }

    native void onBytes(byte[] json);

    native void onFrame(byte[] json, byte[] bytes);

    /** The engine's HermesNative.complete: {@code error} null when the call succeeded. */
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

    /** An error as ember's app says it (SecureStore.errorText): the exception's class and its message. */
    private static String errorText(Throwable e) {
        return e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "");
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

    // ── secure.* (ember client/core-ts hosts/bridge.ts) ──
    //   secure.get {key, user, reason} → {} + the bytes, or {none: true}; secure.set {key, user} + the bytes → {};
    //   secure.delete {key} → {}; secure.ask, and `user` (asking the person: biometrics), not yet.
    // Each value a file of <data>/secure (the key's UTF-8 in hex), sealed with AES-GCM under one key of the Android
    // Keystore, which never leaves it; the value's name is the cipher's associated data, so one file can't stand in
    // for another.

    private static final String ALIAS = "dev.mbui.core.secure";

    private Answer secure(String op, JSONObject a, byte[] bytes) throws Exception {
        if (op.equals("secure.ask") || a.optBoolean("user")) throw new Unsupported();
        String key = a.optString("key", "");
        if (key.isEmpty()) throw new IllegalArgumentException("no key");
        File file = new File(new File(dataDir, "secure"), hex(key.getBytes(StandardCharsets.UTF_8)));
        switch (op) {
            case "secure.get": {
                if (!file.exists()) return new Answer("{\"none\":true}", null);
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
                File dir = file.getParentFile();
                if (!dir.isDirectory() && !dir.mkdirs()) throw new IllegalStateException("no directory for it");
                File tmp = new File(dir, file.getName() + ".tmp");
                try (FileOutputStream f = new FileOutputStream(tmp)) {
                    f.write(iv);
                    f.write(out);
                    f.getFD().sync();
                }
                if (!tmp.renameTo(file)) throw new IllegalStateException("not written");
                return new Answer("{}", null);
            }
            case "secure.delete":
                file.delete();
                return new Answer("{}", null);
            default:
                throw new Unsupported();
        }
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
                Host.log("SECURE_TEST " + (ok ? "ok" : "FAILED") + " in " + (System.nanoTime() - t0) / 1_000_000 + " ms (Android Keystore, AES-GCM)");
            } catch (Throwable e) {
                Host.log("SECURE_TEST FAILED: " + errorText(e));
            }
        });
    }

    private static synchronized SecretKey sealingKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.getKey(ALIAS, null) instanceof SecretKey k) return k;
        KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return g.generateKey();
    }

    private static String hex(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x & 0xff));
        return s.toString();
    }

    // ── for android_core.c, on the UI's (GL) thread ──

    /** Where the core keeps its files: the app's own files, never another app's. */
    static String dataDir() {
        File d = new File(Host.activity.getFilesDir(), "core");
        d.mkdirs();
        return d.getAbsolutePath();
    }

    /** An asset of the APK (the core's bytecode), or null. */
    static byte[] asset(String name) {
        try (InputStream in = Host.activity.getAssets().open(name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[1 << 16];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }
}
