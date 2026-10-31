package dev.mbui;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/**
 * The app keeping itself current (@hostapi.update_install, still.fail's Updates.kt and Install.kt): a newer build the core
 * found (`app.update`) downloaded into the cache, picking up where a cut connection left off (the bytes so far kept in
 * `<name>.part`, the rest asked for as a range, a few times over with a growing pause while each try gets further),
 * checked against its sha256, and handed to the system's installer, which installs it over this one once the person
 * agrees. Installing apps needs the person's leave (安装未知应用): without it the system's page for it opens instead. How
 * it goes the app reads (`state`, on the GL thread: the phase, how far, what went wrong), told each time it changes
 * (`changed`).
 */
final class Updates {
    /** idle | allow (the person's leave asked) | downloading | retrying | installing | handed | failed */
    static volatile String phase = "idle";
    static volatile int percent = -1;
    static volatile String error = "";
    static Thread worker;
    /** Tries in a row that got no further before a download gives up (pauses 1, 2, 4, 8, 16 s between them). */
    static final int RETRIES = 6;

    /**
     * How it goes changed (Native.OUTSIDE_UPDATE): `state` 0 while the host works at it, 1 once it does no more (handed
     * to the installer, the person's leave asked), -1 failed.
     */
    static void changed(int state) {
        Native.tell(Native.OUTSIDE_UPDATE, 1, state);
    }

    static int versionCode() {
        Context c = Host.activity;
        if (c == null) return 0;
        try {
            return (int) c.getPackageManager().getPackageInfo(c.getPackageName(), 0).getLongVersionCode();
        } catch (PackageManager.NameNotFoundException e) {
            return 0;
        }
    }

    static String state() {
        try {
            return new org.json.JSONObject().put("phase", phase).put("percent", percent).put("error", error).toString();
        } catch (org.json.JSONException e) {
            return "";
        }
    }

    /** The build asked for while the person's leave was asked (url, sha256, size, name): taken up as they come back. */
    static Object[] waiting;

    static synchronized void install(String url, String sha256, double size, String name) {
        Context c = Host.activity;
        if (c == null || (worker != null && worker.isAlive())) return;
        if (!c.getPackageManager().canRequestPackageInstalls()) {
            phase = "allow";
            waiting = new Object[] {url, sha256, size, name};
            Host.log("update: the person's leave to install apps asked for");
            c.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + c.getPackageName()))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            changed(1);
            return;
        }
        waiting = null;
        Context app = c.getApplicationContext();
        phase = "downloading";
        percent = -1;
        error = "";
        changed(0);
        worker = new Thread(() -> {
            try {
                File apk = download(app, url, sha256, (long) size, name);
                phase = "installing";
                changed(0);
                installApk(app, apk);
                phase = "handed";
                Host.log("update: " + apk.getName() + " handed to the system's installer");
            } catch (Exception e) {
                phase = "failed";
                error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                Host.log("update failed: " + error);
            }
            changed(phase.equals("failed") ? -1 : 1);
        }, "mbui-update");
        worker.start();
    }

    /**
     * The app back in front (MainActivity.onResume): the build asked for while the person's leave was asked goes on
     * once they gave it, as though asked again; not given, it waits (the system's page is not opened again).
     */
    static synchronized void resumed() {
        Object[] w = waiting;
        Context c = Host.activity;
        if (w == null || !phase.equals("allow") || c == null || !c.getPackageManager().canRequestPackageInstalls()) return;
        Host.log("update: the person's leave to install apps given, the download goes on");
        install((String) w[0], (String) w[1], (Double) w[2], (String) w[3]);
    }

    static File download(Context c, String url, String sha256, long size, String name) throws IOException, InterruptedException {
        File dir = new File(c.getCacheDir(), "updates");
        dir.mkdirs();
        File apk = new File(dir, name);
        File part = new File(dir, name + ".part");
        File[] old = dir.listFiles();
        if (old != null) for (File f : old) if (!f.equals(part) && !f.equals(apk)) f.delete();
        if (apk.exists()) {
            if (sha256(apk).equalsIgnoreCase(sha256)) return apk;
            apk.delete();
        }
        if (size > 0 && part.length() > size) part.delete();
        int failures = 0;
        while (size <= 0 || part.length() < size) {
            long before = part.length();
            try {
                if (fetch(url, part, size)) break;
            } catch (IOException e) {
                if (part.length() > before) failures = 0;
                if (++failures >= RETRIES) throw e;
                phase = "retrying";
                changed(0);
                Thread.sleep(1000L << (failures - 1));
                phase = "downloading";
                changed(0);
            }
        }
        String got = sha256(part);
        if (!got.equalsIgnoreCase(sha256)) {
            part.delete();
            throw new IOException("incomplete");
        }
        if (!part.renameTo(apk)) throw new IOException("incomplete");
        Host.log("update: " + name + " downloaded (" + apk.length() + " bytes), sha256 " + got + " as the feed says");
        return apk;
    }

    /** One try: appends to `part` from where it ends. Whether the file is whole. */
    static boolean fetch(String url, File part, long size) throws IOException {
        long have = part.length();
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(15_000);
        conn.setReadTimeout(30_000);
        if (have > 0) conn.setRequestProperty("Range", "bytes=" + have + "-");
        try {
            int status = conn.getResponseCode();
            if (status == 416) return true;
            if (status >= 500) throw new IOException("status " + status);
            if (status != 200 && status != 206) throw new IllegalStateException("status " + status);
            boolean append = status == 206;
            long done = append ? have : 0;
            try (InputStream in = conn.getInputStream(); OutputStream out = new FileOutputStream(part, append)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) >= 0) {
                    out.write(buf, 0, n);
                    done += n;
                    int p = size > 0 ? (int) (done * 100 / size) : -1;
                    if (p != percent) {
                        percent = p;
                        changed(0);
                    }
                }
            }
            if (size > 0 && done < size) throw new IOException("connection closed at " + done + " of " + size);
            return true;
        } finally {
            conn.disconnect();
        }
    }

    static String sha256(File f) throws IOException {
        try {
            MessageDigest d = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new FileInputStream(f)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) >= 0) d.update(buf, 0, n);
            }
            StringBuilder sb = new StringBuilder();
            for (byte b : d.digest()) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IOException(e);
        }
    }

    /**
     * A package the app has (an APK of a chat: @hostapi.install_package, still.fail's FilePreview.kt install) handed to the
     * system's installer, which asks the person to confirm, its bytes written and committed on a thread of their own.
     * When the app may not install apps yet, the system's page for that leave opens instead (as Install.kt mayInstall).
     * What comes of it, when it is not installed, comes to the app on its system channel ({"install": {"name", "allow"}}
     * or {"install": {"name", "error"}}: src/hostapi/system.mbt), so a run's tape has it.
     */
    static void installPackage(String name, byte[] bytes) {
        Context c = Host.activity;
        if (c == null) {
            installSaid(name, "error", "not_in_front");
            return;
        }
        if (!c.getPackageManager().canRequestPackageInstalls()) {
            c.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + c.getPackageName()))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            installSaid(name, "allow", Boolean.TRUE);
            return;
        }
        Context app = c.getApplicationContext();
        new Thread(() -> {
            try {
                File dir = new File(app.getCacheDir(), "installs");
                dir.mkdirs();
                File apk = new File(dir, new File(name).getName());
                try (OutputStream out = new FileOutputStream(apk)) {
                    out.write(bytes);
                }
                commit(app, apk, false, name);
                Host.log("install: " + name + " handed to the system's installer");
            } catch (Exception e) {
                installFailed(name, e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
            }
        }, "mbui-install").start();
    }

    /** A package's install failed: said to the app (src/hostapi/system.mbt `install`). */
    static void installFailed(String name, String error) {
        Host.log("install: " + name + " failed: " + error);
        installSaid(name, "error", error);
    }

    private static void installSaid(String name, String key, Object value) {
        try {
            Native.post("system", new org.json.JSONObject().put("install", new org.json.JSONObject().put("name", name).put(key, value)).toString());
        } catch (org.json.JSONException ignored) {
        }
    }

    /** The build handed to the installer, as this app's own newer one (installed over it without asking where allowed). */
    static void installApk(Context c, File apk) throws IOException {
        commit(c, apk, true, apk.getName());
    }

    /** `apk` committed to the installer; `self`: this app's own newer build. */
    static void commit(Context c, File apk, boolean self, String name) throws IOException {
        PackageInstaller installer = c.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        if (self) {
            params.setAppPackageName(c.getPackageName());
            if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
        }
        params.setSize(apk.length());
        int id = installer.createSession(params);
        try (PackageInstaller.Session session = installer.openSession(id)) {
            try (OutputStream out = session.openWrite("update.apk", 0, apk.length()); InputStream in = new FileInputStream(apk)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
                session.fsync(out);
            }
            Intent intent = new Intent(c, InstallResult.class).putExtra(InstallResult.SELF, self).putExtra(InstallResult.NAME, name);
            // the installer puts its status in the intent: it has to be mutable
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            session.commit(PendingIntent.getBroadcast(c, id, intent, flags).getIntentSender());
        }
    }

    /** What the installer says of a commit: it wants the person to confirm (its page is opened), or it failed. */
    public static final class InstallResult extends BroadcastReceiver {
        static final String SELF = "self", NAME = "name";

        @Override
        public void onReceive(Context context, Intent intent) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                @SuppressWarnings("deprecation")
                Intent confirm = Build.VERSION.SDK_INT >= 33 ? intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent.class)
                        : intent.getParcelableExtra(Intent.EXTRA_INTENT);
                if (confirm == null) return;
                Host.log("update: the installer asks the person to confirm");
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } else if (status != PackageInstaller.STATUS_SUCCESS && status != PackageInstaller.STATUS_FAILURE_ABORTED) {
                String m = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                if (!intent.getBooleanExtra(SELF, true)) {
                    installFailed(intent.getStringExtra(NAME), m == null ? "install failed" : m);
                    return;
                }
                phase = "failed";
                error = m == null ? "install failed" : m;
                Host.log("update: the installer failed: " + error);
                changed(-1);
            }
        }
    }
}
