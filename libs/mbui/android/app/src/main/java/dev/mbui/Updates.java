package dev.mbui;

import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;

/**
 * The app keeping itself current (@hostapi.update_fetch, update_apply): a newer
 * build the core found (`app.update`) downloaded by itself into the app's files (`fetch`), picking up where a cut
 * connection left off (the bytes so far kept in `<name>.part`, the rest asked for as a range, a few times over with a
 * growing pause while each try gets further), checked against its sha256 and kept: ready. On a metered network it waits
 * for one that is not (a job), unless the person asked for it. A build ready is put in place while the person is away
 * from the app: once it has been out of sight for AWAY_MS (a job; not while a sign-in waits in the browser), handed to
 * the system's installer, which installs it over this one without asking (UPDATE_PACKAGES_WITHOUT_USER_ACTION), so
 * the app opened next is the newer build. Asked to put it in place now (`apply`), it is at once: the app ends (no app
 * may open itself again from behind), and the newer build says so in a notification that opens it. Installing apps
 * needs the person's leave (安装未知应用): asked now without it, the system's page for it opens and, once given, the
 * build goes in; found missing while away, the app is told (phase allow) and the build waits. How it goes the app
 * reads (`state`, on the GL thread: the phase, how far, what went wrong, the build), told each time it changes
 * (`changed`). What it asked for and the build ready are kept in the app's files: a job of a later run takes them up.
 *
 * Where the core names a delta from this build (`delta`, scripts/delta.ts's format), it is tried first, on the same
 * worker and network rule: downloaded the same resumable way (`<name>.delta.part`, how far against its own size),
 * checked, made into the package against the installed APK (Delta.apply) and checked against the package's own sha256;
 * then on as if the package had been downloaded. Anything wrong with it is logged and the whole package downloaded as
 * before: the person never sees a delta fail. It is kept with what was asked for, so a later run takes the same way.
 */
final class Updates {
    /** idle | waiting (for a network that is not metered) | downloading | retrying | ready | allow | installing | failed */
    static volatile String phase = "idle";
    static volatile int percent = -1;
    static volatile String error = "";
    /** The build asked for, by its file's name ("" none). */
    static volatile String file = "";
    static Thread worker;
    /** Tries in a row that got no further before a download gives up (pauses 1, 2, 4, 8, 16 s between them). */
    static final int RETRIES = 6;
    /** How long the app is out of sight before a build ready is put in place. */
    static final long AWAY_MS = 10 * 60_000L;
    static final int FETCH_JOB = 7201, AWAY_JOB = 7202;
    /** Whether the app's window is on the screen (MainActivity's onStart to onStop). */
    static volatile boolean inSight;
    /** The person asked for the build to go in now, and the leave to install apps was asked first; what it says after. */
    static volatile String nowSaid;
    private static boolean restored;

    /**
     * How it goes changed (Native.OUTSIDE_UPDATE): `state` 0 while the host works at it, 1 once it does no more (ready,
     * waiting, the person's leave wanted), -1 failed.
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
        Context c = app();
        if (c != null) restore(c);
        try {
            // (`away`: a build ready is put in place by itself while the app is out of sight)
            return new org.json.JSONObject().put("phase", phase).put("percent", percent).put("error", error).put("file", file)
                    .put("away", true).toString();
        } catch (org.json.JSONException e) {
            return "";
        }
    }

    private static Context app() {
        Context c = Host.activity;
        return c == null ? null : c.getApplicationContext();
    }

    /** Where the builds are kept: the app's files' updates/ (what is asked for in `asked`, a build whole once ready). */
    static File dir(Context c) {
        File d = new File(c.getFilesDir(), "updates");
        d.mkdirs();
        return d;
    }

    /** The build whole and checked in `dir` (its name, the newest), newer than this one; null none. */
    private static File readyIn(Context c) {
        File[] all = dir(c).listFiles();
        if (all == null) return null;
        long mine;
        try {
            mine = c.getPackageManager().getPackageInfo(c.getPackageName(), 0).getLongVersionCode();
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
        File best = null;
        long bestCode = mine;
        for (File f : all) {
            if (!f.getName().endsWith(".apk")) continue;
            PackageInfo p = c.getPackageManager().getPackageArchiveInfo(f.getPath(), 0);
            long code = p == null ? 0 : p.getLongVersionCode();
            if (code > bestCode) {
                if (best != null) best.delete();
                best = f;
                bestCode = code;
            } else {
                // this build's, or older: put in place already, or never to be
                f.delete();
            }
        }
        return best;
    }

    /**
     * What an earlier run left, taken up once: a build ready (ready again), what it had asked for (still asked for:
     * waiting); the cache's updates/ of builds before these were kept in the app's files, let go.
     */
    static synchronized void restore(Context c) {
        if (restored) return;
        restored = true;
        deleteAll(new File(c.getCacheDir(), "updates"));
        File ready = readyIn(c);
        String[] asked = asked(c);
        if (ready != null) {
            file = ready.getName();
            phase = "ready";
        } else if (asked != null) {
            file = asked[3];
            phase = "waiting";
        }
    }

    private static void deleteAll(File d) {
        File[] all = d.listFiles();
        if (all != null) for (File f : all) f.delete();
        d.delete();
    }

    /**
     * What was asked for last: url, sha256, size, name, delta ("" none: as an earlier build, which kept four lines,
     * left it); null none (or the build it names put in place since).
     */
    private static String[] asked(Context c) {
        try {
            String[] a = new String(Files.readAllBytes(new File(dir(c), "asked").toPath()), StandardCharsets.UTF_8).split("\n", -1);
            if (a.length == 4) return new String[]{a[0], a[1], a[2], a[3], ""};
            return a.length == 5 ? a : null;
        } catch (IOException e) {
            return null;
        }
    }

    private static boolean metered(Context c) {
        ConnectivityManager cm = c.getSystemService(ConnectivityManager.class);
        return cm == null || cm.isActiveNetworkMetered();
    }

    /**
     * The build at `url` made ready (@hostapi.update_fetch): downloaded now where the network is not metered or the
     * person asked (`now`), else once one that is not comes (a job). One ready, or coming, of that name: nothing more.
     */
    static synchronized void fetch(String url, String sha256, double size, String name, boolean now, String delta) {
        Context c = app();
        if (c == null) return;
        restore(c);
        name = new File(name).getName();
        if (worker != null && worker.isAlive()) return;
        if (name.equals(file) && (phase.equals("ready") || phase.equals("allow") || phase.equals("installing"))) return;
        // (JSON on a line of its own: the core's has no line breaks, and one that had would only be a delta not used)
        String d = delta == null ? "" : delta.replace('\n', ' ');
        try {
            Files.write(new File(dir(c), "asked").toPath(),
                    (url + "\n" + sha256 + "\n" + (long) size + "\n" + name + "\n" + d).getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) {
            Host.log("update: what is asked for not kept: " + e);
        }
        file = name;
        percent = -1;
        error = "";
        if (!now && metered(c)) {
            phase = "waiting";
            Host.log("update: " + name + " waits for a network that is not metered");
            JobScheduler js = c.getSystemService(JobScheduler.class);
            if (js != null) js.schedule(new JobInfo.Builder(FETCH_JOB, new ComponentName(c, Job.class))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_UNMETERED).setPersisted(false).build());
            changed(1);
            return;
        }
        start(c, url, sha256, (long) size, name, d);
    }

    /** The download on a thread of its own: ready, then put in place once the app is out of sight a while. */
    private static void start(Context c, String url, String sha256, long size, String name, String delta) {
        phase = "downloading";
        // how far from the first: what an earlier try kept (0 none), not "not known" till the first bytes come (the
        // delta's, against its size, where there is one)
        long deltaSize = deltaSize(delta);
        long have = new File(dir(c), name + (deltaSize > 0 ? ".delta.part" : ".part")).length(), of = deltaSize > 0 ? deltaSize : size;
        percent = of > 0 ? (int) (Math.min(have, of) * 100 / of) : -1;
        changed(0);
        worker = new Thread(() -> {
            String result = "ready", why = "";
            try {
                download(c, url, sha256, size, name, delta);
                Host.log("update: " + name + " ready");
            } catch (Exception e) {
                result = "failed";
                why = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                Host.log("update failed: " + why);
            }
            // Publish the result only once another download can be accepted: an earlier progress event may read it
            // before changed() is delivered, and the app may then hand us a newer build right away.
            synchronized (Updates.class) {
                worker = null;
                error = why;
                phase = result;
                if (result.equals("ready") && !inSight) away(c);
                changed(phase.equals("failed") ? -1 : 1);
            }
        }, "mbui-update");
        worker.start();
    }

    /** What was asked for downloaded (FETCH_JOB, on a network that is not metered), waiting till it is whole. */
    static void fetchAsked(Context c) throws InterruptedException {
        Thread w;
        synchronized (Updates.class) {
            restore(c);
            String[] a = asked(c);
            if (a == null || !phase.equals("waiting") || (worker != null && worker.isAlive())) return;
            start(c, a[0], a[1], Long.parseLong(a[2]), a[3], a[4]);
            w = worker;
        }
        w.join();
    }

    /** The app's window on the screen (MainActivity.onStart): a build ready stays out while it is. */
    static void started() {
        inSight = true;
        Context c = app();
        JobScheduler js = c == null ? null : c.getSystemService(JobScheduler.class);
        if (js != null) js.cancel(AWAY_JOB);
    }

    /** The app's window off the screen (MainActivity.onStop): a build ready put in place once it stays so a while. */
    static void stopped() {
        inSight = false;
        Context c = app();
        if (c != null && phase.equals("ready")) away(c);
    }

    private static void away(Context c) {
        JobScheduler js = c.getSystemService(JobScheduler.class);
        if (js != null) js.schedule(new JobInfo.Builder(AWAY_JOB, new ComponentName(c, Job.class))
                .setMinimumLatency(AWAY_MS).setPersisted(false).build());
    }

    /**
     * Out of sight a while (AWAY_JOB): the build ready put in place, unless the app came back meanwhile or a sign-in
     * waits in the browser (then a while later again); without the leave to install apps, the app is told (allow).
     */
    static synchronized void awayLong(Context c) {
        restore(c);
        if (inSight || !phase.equals("ready")) return;
        if (LoginService.listening()) {
            away(c);
            return;
        }
        if (!c.getPackageManager().canRequestPackageInstalls()) {
            phase = "allow";
            Host.log("update: ready, the person's leave to install apps wanted");
            changed(1);
            return;
        }
        put(c, null);
    }

    /**
     * The build ready put in place now (@hostapi.update_apply): the app ends; the newer build says `said` in a
     * notification. Without the leave to install apps, the system's page for it opens first (resumed takes it up).
     */
    static synchronized void apply(String said) {
        Context c = app();
        if (c == null) return;
        restore(c);
        if (!phase.equals("ready") && !phase.equals("allow")) return;
        if (!c.getPackageManager().canRequestPackageInstalls()) {
            phase = "allow";
            nowSaid = said;
            Host.log("update: the person's leave to install apps asked for");
            Host.activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + c.getPackageName()))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            changed(1);
            return;
        }
        put(c, said);
    }

    /**
     * The app back in front (MainActivity.onResume) with the leave to install apps given: the build ready again, put
     * in place now where the person had asked for it now; not given, it waits (the system's page not opened again).
     */
    static synchronized void resumed() {
        Context c = app();
        if (c == null || !phase.equals("allow") || !c.getPackageManager().canRequestPackageInstalls()) return;
        Host.log("update: the person's leave to install apps given");
        phase = "ready";
        String said = nowSaid;
        nowSaid = null;
        if (said != null) put(c, said);
        else changed(1);
    }

    /** The build ready handed to the installer; `said` (put in place now) kept for the newer build's notification. */
    private static void put(Context c, String said) {
        File apk = readyIn(c);
        if (apk == null) {
            phase = "idle";
            file = "";
            changed(1);
            return;
        }
        phase = "installing";
        changed(0);
        File note = new File(dir(c), "said");
        if (said != null) {
            try {
                Files.write(note.toPath(), said.getBytes(StandardCharsets.UTF_8));
            } catch (IOException ignored) {
            }
        } else {
            note.delete();
        }
        new Thread(() -> {
            try {
                installApk(c, apk);
                Host.log("update: " + apk.getName() + " handed to the system's installer");
            } catch (Exception e) {
                phase = "failed";
                error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                Host.log("update failed: " + error);
                changed(-1);
            }
        }, "mbui-update-put").start();
    }

    /** The jobs: what is asked for downloaded on a network that is not metered; the build ready put in while away. */
    public static final class Job extends JobService {
        @Override
        public boolean onStartJob(JobParameters p) {
            Context c = getApplicationContext();
            new Thread(() -> {
                try {
                    if (p.getJobId() == FETCH_JOB) fetchAsked(c);
                    else awayLong(c);
                } catch (Exception e) {
                    Host.log("update job: " + e);
                }
                jobFinished(p, false);
            }, "mbui-update-job").start();
            return true;
        }

        @Override
        public boolean onStopJob(JobParameters p) {
            return false;
        }
    }

    /**
     * The app put in place by the system (MY_PACKAGE_REPLACED, in the newer build): what was kept for it let go; put in
     * place at the person's word, its notification, which opens it.
     */
    public static final class Replaced extends BroadcastReceiver {
        @Override
        public void onReceive(Context c, Intent intent) {
            File d = dir(c);
            File note = new File(d, "said");
            String said = null;
            try {
                said = new String(Files.readAllBytes(note.toPath()), StandardCharsets.UTF_8);
            } catch (IOException ignored) {
            }
            File[] all = d.listFiles();
            if (all != null) for (File f : all) f.delete();
            if (said != null && !said.isEmpty()) Notices.show(c, c.getApplicationInfo().loadLabel(c.getPackageManager()).toString(), "update", said, "", "");
        }
    }

    /** The build downloaded whole into `dir` (made from the delta where one is given and works) and checked against its sha256. */
    static File download(Context c, String url, String sha256, long size, String name, String delta) throws IOException, InterruptedException {
        File dir = dir(c);
        File apk = new File(dir, name);
        File part = new File(dir, name + ".part");
        File deltaPart = new File(dir, name + ".delta.part");
        File[] old = dir.listFiles();
        // (another build's, whole or in part, let go; what is asked for kept, and this one's delta coming)
        if (old != null) for (File f : old) if (!f.equals(part) && !f.equals(apk) && !f.equals(deltaPart) && !f.getName().equals("asked")) f.delete();
        if (apk.exists()) {
            if (sha256(apk).equalsIgnoreCase(sha256)) {
                deltaPart.delete();
                return apk;
            }
            apk.delete();
        }
        if (delta != null && !delta.isEmpty()) {
            try {
                return fromDelta(c, url, sha256, size, name, delta);
            } catch (InterruptedException e) {
                throw e;
            } catch (Exception e) {
                Host.log("update: the delta for " + name + " not used, the whole package instead: "
                        + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                deltaPart.delete();
                new File(dir, name + ".made").delete();
                phase = "downloading";
                percent = size > 0 ? (int) (Math.min(part.length(), size) * 100 / size) : -1;
                changed(0);
            }
        }
        whole(url, part, size);
        String got = sha256(part);
        if (!got.equalsIgnoreCase(sha256)) {
            part.delete();
            throw new IOException("incomplete");
        }
        if (!part.renameTo(apk)) throw new IOException("incomplete");
        Host.log("update: " + name + " downloaded (" + apk.length() + " bytes), sha256 " + got + " as the feed says");
        return apk;
    }

    /** The delta's size from its JSON; 0 none (or not readable: the whole package's way). */
    private static long deltaSize(String delta) {
        if (delta == null || delta.isEmpty()) return 0;
        try {
            return new org.json.JSONObject(delta).optLong("size", 0);
        } catch (org.json.JSONException e) {
            return 0;
        }
    }

    /**
     * The build made from the delta (`delta`: {url, sha256, size, makes_sha256, makes_size}) against the installed APK:
     * downloaded into `<name>.delta.part`, checked, applied into `<name>.made`, that checked against the package's
     * sha256 and put in its place. Throws for anything wrong; the caller lets it go and downloads the package.
     */
    private static File fromDelta(Context c, String url, String sha256, long size, String name, String delta) throws Exception {
        org.json.JSONObject d = new org.json.JSONObject(delta);
        // (on Android the package the delta makes is the APK itself: the feed must say the same of both)
        if (!d.optString("makes_sha256").equalsIgnoreCase(sha256) || (size > 0 && d.optLong("makes_size", -1) != size)) {
            throw new IOException("it makes another package than the one asked for");
        }
        long dsize = d.getLong("size");
        String dsha = d.getString("sha256");
        if (dsize <= 0 || dsha.isEmpty()) throw new IOException("its size or sha256 is missing");
        // (where the feed names it beside the package, relative to it)
        String durl = new URL(new URL(url), d.getString("url")).toString();
        File dir = dir(c);
        File part = new File(dir, name + ".delta.part");
        File made = new File(dir, name + ".made");
        File apk = new File(dir, name);
        whole(durl, part, dsize);
        if (part.length() != dsize || !sha256(part).equalsIgnoreCase(dsha)) {
            part.delete();
            throw new IOException("the delta downloaded is not the one the feed says");
        }
        long t0 = System.currentTimeMillis();
        Delta.apply(new File(c.getApplicationInfo().sourceDir), part, made, dir);
        String got = sha256(made);
        if (!got.equalsIgnoreCase(sha256)) throw new IOException("the package it made is not the feed's (sha256 " + got + ")");
        if (!made.renameTo(apk)) throw new IOException("the package it made could not be kept");
        part.delete();
        Host.log("update: " + name + " made from a delta of " + dsize + " bytes (in " + (System.currentTimeMillis() - t0)
                + " ms), sha256 " + got + " as the feed says");
        return apk;
    }

    /** `url` downloaded into `part` till it is `size` bytes (or whole, size unknown), picking up where it was left. */
    private static void whole(String url, File part, long size) throws IOException, InterruptedException {
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
     * A package the app has (an APK of a chat: @hostapi.install_package) handed to the
     * system's installer, which asks the person to confirm, its bytes written and committed on a thread of their own.
     * When the app may not install apps yet, the system's page for that leave opens instead.
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
                boolean self = intent.getBooleanExtra(SELF, true);
                if (self && !inSight) {
                    // (the system's page could not open from behind: ready again, for the person's word)
                    Host.log("update: the installer asks the person to confirm, away: ready again");
                    phase = "ready";
                    changed(1);
                    return;
                }
                Host.log("update: the installer asks the person to confirm");
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } else if (status == PackageInstaller.STATUS_FAILURE_ABORTED) {
                // the person said no to the system's page: ready again
                if (intent.getBooleanExtra(SELF, true) && phase.equals("installing")) {
                    phase = "ready";
                    changed(1);
                }
            } else if (status != PackageInstaller.STATUS_SUCCESS) {
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
