package dev.mbui;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyStore;
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
    /** Off the core's thread: the Keystore takes its time. */
    private static final ExecutorService calls = Executors.newSingleThreadExecutor();

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
    synchronized void closing() {
        closed = true;
        notifyAll();
    }

    void onApp(long id, String op, byte[] json, byte[] bytes) {
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
        });
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
