package dev.mbui;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/**
 * The app's crashes, to still.fail's PostHog project as {@code $exception} events, as still.fail's Android app sends
 * them (apps/android/app/src/main/kotlin/fail/still/android/Crashes.kt; docs/telemetry.md → 安卓). A crash in Java is
 * written down as it happens (its exception, which the system does not keep); at the next start, once an account is
 * signed in (src/stillfail/reports.mbt), the system's record of how the app's processes ended (ApplicationExitInfo) is
 * read from where the last start left off, and each crash, native abort (Hermes, the core's JNI, the MoonBit app's C)
 * or ANR goes out, with what the system kept of it: a native crash's tombstone (Tombstone.java), an ANR's thread dump.
 * A build without PostHog's key (a local or dev one: build.gradle.kts, STILLFAIL_POSTHOG) sends nothing, nor one whose
 * person turned it off ({@link #reporting}): everything the app sends to PostHog goes by {@link #send}.
 */
final class Crashes {
    private Crashes() {}

    private static final String DIR = "crashes";
    /** Where the last report left off in the system's record (its timestamp, ms). */
    private static final String SINCE = "crashes.since";
    /** How far back the first start with this looks: the crashes from before it are what we want to see first. */
    private static final long LOOK_BACK = 7L * 24 * 3600 * 1000;
    /** At most this many each start, the newest. */
    private static final int MOST = 20;
    /** What goes up of one crash's trace, as the {@code trace} property. */
    static final int LOGS = 60 * 1024;
    /** A tombstone read at most this far (they carry memory dumps). */
    private static final int TOMBSTONE = 4 * 1024 * 1024;
    /** What goes up of the log a native crash left, as the {@code logcat} property. */
    private static final int LOGGED = 80;
    private static final int LOGGED_BYTES = 16 * 1024;
    /** Where the core's restarts are told from: the account the last report went as (they come before one is known). */
    private static final String ACCOUNT = "crashes.account";
    /** Whether usage statistics and error reports go out from this device: yes until turned off; this device's only. */
    private static final String REPORTING = "telemetry";

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("stillfail", Context.MODE_PRIVATE);
    }

    /** This build's PostHog project and its version, read as the app starts (install): its resources (build.gradle.kts
     *  puts them there) and its package's versionName. */
    private static String posthogHost = "";
    private static String posthogKey = "";
    private static String versionName = "";
    /** Which app this is (the manifest's dev.mbui.env, android/apk.json's variants): still.fail's own (stable or beta,
     *  MBUI_OWN) or the build of every push beside it (still.fail mbui); a beta's (MBUI_BETA). */
    private static boolean own, beta;

    static boolean hasKey() {
        return !posthogKey.isEmpty();
    }

    /** Keeps a Java crash's exception in the app's files before the system's handler ends the process. */
    static void install(Context context) {
        posthogHost = context.getString(R.string.posthog_host);
        posthogKey = context.getString(R.string.posthog_key);
        try {
            String v = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
            versionName = v != null ? v : "";
        } catch (Exception e) {
            versionName = "";
        }
        own = "1".equals(Push.env(context, "MBUI_OWN"));
        beta = "1".equals(Push.env(context, "MBUI_BETA"));
        Thread.UncaughtExceptionHandler before = Thread.getDefaultUncaughtExceptionHandler();
        if (before instanceof Keeper) return;
        Thread.setDefaultUncaughtExceptionHandler(new Keeper(new File(context.getFilesDir(), DIR), before));
    }

    private static final class Keeper implements Thread.UncaughtExceptionHandler {
        final File dir;
        final Thread.UncaughtExceptionHandler next;

        Keeper(File dir, Thread.UncaughtExceptionHandler next) {
            this.dir = dir;
            this.next = next;
        }

        @Override
        public void uncaughtException(Thread thread, Throwable e) {
            try {
                dir.mkdirs();
                JSONObject kept = new JSONObject();
                kept.put("thread", thread.getName());
                kept.put("exceptions", exceptions(e));
                kept.put("stack", take(stack(e), LOGS));
                Files.write(new File(dir, System.currentTimeMillis() + ".json").toPath(), kept.toString().getBytes(StandardCharsets.UTF_8));
            } catch (Throwable ignored) {
            }
            if (next != null) next.uncaughtException(thread, e);
        }
    }

    private static String stack(Throwable e) {
        StringWriter w = new StringWriter();
        e.printStackTrace(new PrintWriter(w));
        return w.toString();
    }

    /** A throwable and its causes as PostHog's {@code $exception_list} (as posthog-android's ThrowableCoercer makes it). */
    static JSONArray exceptions(Throwable e) throws Exception {
        JSONArray out = new JSONArray();
        Set<Throwable> seen = Collections.newSetFromMap(new java.util.IdentityHashMap<>());
        Throwable t = e;
        while (t != null && seen.add(t) && seen.size() <= 4) {
            JSONObject x = new JSONObject();
            Package p = t.getClass().getPackage();
            String pkg = p != null ? p.getName() : null;
            String name = t.getClass().getName();
            x.put("type", pkg != null && name.startsWith(pkg + ".") ? name.substring(pkg.length() + 1) : name);
            if (t.getMessage() != null && !t.getMessage().isEmpty()) x.put("value", t.getMessage());
            if (pkg != null) x.put("module", pkg);
            x.put("mechanism", new JSONObject().put("handled", false).put("synthetic", false).put("type", t == e ? "generic" : "chained"));
            // Bottom-up: the crash site last.
            StackTraceElement[] st = t.getStackTrace();
            List<StackTraceElement> frames = new ArrayList<>();
            for (int i = st.length - 1; i >= 0; i--) frames.add(st[i]);
            if (frames.size() > 64) frames = frames.subList(frames.size() - 64, frames.size());
            if (!frames.isEmpty()) {
                JSONArray fs = new JSONArray();
                for (StackTraceElement f : frames) {
                    JSONObject j = new JSONObject();
                    j.put("module", f.getClassName());
                    j.put("function", f.getMethodName());
                    j.put("platform", "java");
                    if (f.getFileName() != null) j.put("filename", f.getFileName());
                    if (f.getLineNumber() >= 0) j.put("lineno", f.getLineNumber());
                    // this app's own: the host's and still.fail's Java (dev.mbui), as fail.still.* is the Android app's
                    j.put("in_app", f.getClassName().startsWith("dev.mbui."));
                    fs.put(j);
                }
                x.put("stacktrace", new JSONObject().put("type", "raw").put("frames", fs));
            }
            out.put(x);
            t = t.getCause();
        }
        return out;
    }

    private static final class Report {
        final long at;
        final int pid;
        final JSONArray exceptions;
        final String fingerprint, trace;
        final JSONObject facts;
        final File kept;

        Report(long at, int pid, JSONArray exceptions, String fingerprint, String trace, JSONObject facts, File kept) {
            this.at = at;
            this.pid = pid;
            this.exceptions = exceptions;
            this.fingerprint = fingerprint;
            this.trace = trace;
            this.facts = facts;
            this.kept = kept;
        }
    }

    /** The core died and is started again (src/core's restart, @core.on_failed): not a crash of the app, but what
     *  leads to one, and the reason is the only trace of the core's own bug. Sent at once, as the web's CoreFailed is. */
    static void coreFailed(Context context, String reason) {
        handled(context, "CoreFailed", take(reason, 1000), "core_failed", null);
    }

    /** The native heap past MemoryWatch's limit, with what was under way then (MemoryWatch.java). */
    static void memoryRunaway(Context context, String value, JSONObject facts) {
        handled(context, "MemoryRunaway", value, "memory_runaway", facts);
    }

    /** An error the app got past, sent at once as {@code type} with {@code value}, {@code reason} and {@code facts}. */
    private static void handled(Context context, String type, String value, String reason, JSONObject facts) {
        if (!hasKey()) return;
        String known = account(context);
        String account = known != null ? known : "android-anonymous";
        long at = System.currentTimeMillis();
        int pid = android.os.Process.myPid();
        new Thread(() -> {
            try {
                JSONArray ex = new JSONArray().put(new JSONObject().put("type", type).put("value", value)
                        .put("mechanism", new JSONObject().put("handled", true).put("synthetic", false).put("type", "generic")));
                JSONObject f = new JSONObject().put("reason", reason);
                if (facts != null) for (Iterator<String> k = facts.keys(); k.hasNext(); ) {
                    String key = k.next();
                    f.put(key, facts.get(key));
                }
                List<JSONObject> batch = new ArrayList<>();
                batch.add(event(new Report(at, pid, ex, null, null, f, null), account, "error"));
                send(context, batch);
            } catch (Exception ignored) {
            }
        }).start();
    }

    static boolean reporting(Context context) {
        return prefs(context).getBoolean(REPORTING, true);
    }

    /** Turned on or off on this device (the settings' 「发送使用统计和错误报告」: src/sfapp/settings/home.mbt). */
    static void setReporting(Context context, boolean on) {
        prefs(context).edit().putBoolean(REPORTING, on).apply();
    }

    /** The account the last report went as (the signed-in one's id): what the app's other events go as (BarTiming). */
    static String account(Context context) {
        return prefs(context).getString(ACCOUNT, null);
    }

    /** What every event of the app carries: its build, and the device. */
    static JSONObject device() throws Exception {
        JSONObject d = new JSONObject();
        d.put("release", versionName);
        // still.fail's Android app ("android", the beta's told apart by `beta`), or the build of every push beside it
        // ("android-mbui"): its crashes and timings not counted as the released app's
        d.put("app", own ? "android" : "android-mbui");
        d.put("beta", beta);
        d.put("$app_version", versionName);
        d.put("$os", "Android");
        d.put("$os_version", Build.VERSION.RELEASE);
        d.put("$device_manufacturer", Build.MANUFACTURER);
        d.put("$device_model", Build.MODEL);
        d.put("$lib", own ? "stillfail-android" : "stillfail-mbui-android");
        return d;
    }

    /** Sends what crashed since the last start, as {@code account} (the signed-in account's id, the web's distinct
     *  id), off the calling thread; what fails to go (offline) goes at the next start. */
    static void report(Context context, String account) {
        if (!hasKey()) return;
        SharedPreferences prefs = prefs(context);
        prefs.edit().putString(ACCOUNT, account).apply();
        new Thread(() -> {
            List<Report> reports = gather(context, prefs.getLong(SINCE, System.currentTimeMillis() - LOOK_BACK));
            if (reports.isEmpty()) return;
            long last = 0;
            try {
                List<JSONObject> batch = new ArrayList<>();
                for (Report r : reports) {
                    batch.add(event(r, account, "fatal"));
                    last = Math.max(last, r.at);
                }
                send(context, batch);
            } catch (Exception e) {
                return;
            }
            prefs.edit().putLong(SINCE, last).apply();
            for (Report r : reports) if (r.kept != null) r.kept.delete();
        }, "stillfail-crashes").start();
    }

    private static JSONObject event(Report r, String account, String level) throws Exception {
        JSONObject e = new JSONObject();
        e.put("event", "$exception");
        e.put("distinct_id", account);
        // The same crash sent again (its answer lost) is the same event: PostHog keeps one.
        e.put("uuid", UUID.nameUUIDFromBytes(("android-mbui-" + level + "-" + r.at + "-" + r.pid).getBytes(StandardCharsets.UTF_8)).toString());
        e.put("timestamp", iso(r.at));
        JSONObject p = new JSONObject();
        p.put("$exception_list", r.exceptions);
        p.put("$exception_level", level);
        if (r.fingerprint != null) p.put("$exception_fingerprint", r.fingerprint);
        if (r.trace != null) p.put("trace", r.trace);
        JSONObject d = device();
        for (Iterator<String> k = d.keys(); k.hasNext(); ) {
            String key = k.next();
            p.put(key, d.get(key));
        }
        for (Iterator<String> k = r.facts.keys(); k.hasNext(); ) {
            String key = k.next();
            p.put(key, r.facts.get(key));
        }
        e.put("properties", p);
        return e;
    }

    /** Everything the app sends to PostHog. Turned off, nothing goes, and what was to go is not kept for later (report
     *  moves on past the crashes as if they had gone). */
    static void send(Context context, List<JSONObject> batch) throws Exception {
        if (!hasKey() || !reporting(context)) return;
        JSONArray all = new JSONArray();
        for (JSONObject e : batch) all.put(e);
        byte[] body = new JSONObject().put("api_key", posthogKey).put("batch", all).toString().getBytes(StandardCharsets.UTF_8);
        String host = posthogHost;
        while (host.endsWith("/")) host = host.substring(0, host.length() - 1);
        HttpURLConnection c = (HttpURLConnection) new URL(host + "/batch/").openConnection();
        try {
            c.setRequestMethod("POST");
            c.setConnectTimeout(15_000);
            c.setReadTimeout(15_000);
            c.setDoOutput(true);
            c.setRequestProperty("content-type", "application/json");
            try (OutputStream out = c.getOutputStream()) {
                out.write(body);
            }
            int status = c.getResponseCode();
            if (status < 200 || status > 299) throw new java.io.IOException("posthog answered " + status);
        } finally {
            c.disconnect();
        }
    }

    private static List<Report> gather(Context context, long since) {
        File dir = new File(context.getFilesDir(), DIR);
        List<long[]> keptAt = new ArrayList<>();
        List<File> keptFiles = new ArrayList<>();
        File[] files = dir.listFiles();
        if (files != null) for (File f : files) {
            String n = f.getName();
            if (!n.endsWith(".json")) continue;
            try {
                keptAt.add(new long[] {Long.parseLong(n.substring(0, n.length() - 5))});
                keptFiles.add(f);
            } catch (NumberFormatException ignored) {
            }
        }
        List<Report> made = ended(context, since, keptAt, keptFiles);
        // An exception kept with no end recorded (the record cleared, or older than it goes back): on its own.
        for (int i = 0; i < keptAt.size(); i++) {
            long at = keptAt.get(i)[0];
            if (at > since) made.add(javaOnly(at, keptFiles.get(i)));
            else keptFiles.get(i).delete();
        }
        made.sort((a, b) -> Long.compare(a.at, b.at));
        return made.size() > MOST ? new ArrayList<>(made.subList(made.size() - MOST, made.size())) : made;
    }

    /** The crashes and ANRs in the system's record since {@code since}, each with its exception kept here (taken out
     *  of the kept ones). */
    private static List<Report> ended(Context context, long since, List<long[]> keptAt, List<File> keptFiles) {
        List<ApplicationExitInfo> exits;
        try {
            exits = context.getSystemService(ActivityManager.class).getHistoricalProcessExitReasons(context.getPackageName(), 0, 0);
        } catch (Exception e) {
            exits = Collections.emptyList();
        }
        List<Report> out = new ArrayList<>();
        for (ApplicationExitInfo exit : exits) {
            int r = exit.getReason();
            boolean wanted = r == ApplicationExitInfo.REASON_CRASH || r == ApplicationExitInfo.REASON_CRASH_NATIVE || r == ApplicationExitInfo.REASON_ANR;
            if (exit.getTimestamp() <= since || !(wanted || killedInSight(exit))) continue;
            // The exception written down as it crashed: the file made just before the system recorded the end.
            File file = null;
            if (r == ApplicationExitInfo.REASON_CRASH) {
                int best = -1;
                for (int i = 0; i < keptAt.size(); i++) {
                    long at = keptAt.get(i)[0];
                    if (at >= exit.getTimestamp() - 10_000 && at <= exit.getTimestamp() + 1_000 && (best < 0 || at > keptAt.get(best)[0])) best = i;
                }
                if (best >= 0) {
                    file = keptFiles.remove(best);
                    keptAt.remove(best);
                }
            }
            out.add(of(exit, file));
        }
        return out;
    }

    /** The reasons the system ends a process for that the person sees as a crash when the app is in front of them (it
     *  vanishes to the home screen) and the app itself never gets to tell: out of memory, an OEM's resource manager. */
    private static String killed(int reason) {
        switch (reason) {
            case ApplicationExitInfo.REASON_LOW_MEMORY: return "low_memory";
            case ApplicationExitInfo.REASON_SIGNALED: return "signaled";
            case ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE: return "excessive_resource_usage";
            case ApplicationExitInfo.REASON_INITIALIZATION_FAILURE: return "initialization_failure";
            case ApplicationExitInfo.REASON_DEPENDENCY_DIED: return "dependency_died";
            case ApplicationExitInfo.REASON_OTHER: return "other";
            default: return null;
        }
    }

    /** Killed for one of {@link #killed}'s reasons while on screen (killed in the background is how Android works). */
    private static boolean killedInSight(ApplicationExitInfo exit) {
        return killed(exit.getReason()) != null && exit.getImportance() <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE;
    }

    private static Report of(ApplicationExitInfo exit, File kept) {
        int reason = exit.getReason();
        String trace = null;
        try (InputStream in = exit.getTraceInputStream()) {
            if (in != null) {
                trace = reason == ApplicationExitInfo.REASON_CRASH_NATIVE ? Tombstone.text(readAtMost(in, TOMBSTONE))
                        : take(new String(readAtMost(in, Integer.MAX_VALUE), StandardCharsets.UTF_8), LOGS);
            }
        } catch (Exception ignored) {
            trace = null;
        }
        String description = exit.getDescription() != null ? exit.getDescription() : "";
        try {
            JSONObject facts = new JSONObject();
            facts.put("reason", reason == ApplicationExitInfo.REASON_CRASH ? "crash"
                    : reason == ApplicationExitInfo.REASON_CRASH_NATIVE ? "crash_native"
                    : reason == ApplicationExitInfo.REASON_ANR ? "anr" : "killed_" + killed(reason));
            facts.put("exit_status", exit.getStatus());
            if (exit.getDescription() != null) facts.put("exit_description", exit.getDescription());
            facts.put("process", exit.getProcessName());
            facts.put("importance", exit.getImportance());
            facts.put("pss_kb", exit.getPss());
            facts.put("rss_kb", exit.getRss());
            if (reason != ApplicationExitInfo.REASON_CRASH) {
                // The system's WebView draws in the app's own render thread, and a crash in it has no symbols to read:
                // its version says which Chromium it was, and what it logged before it ended says why.
                if (reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                    String w = webView();
                    if (w != null) facts.put("webview", w);
                }
                if (reason != ApplicationExitInfo.REASON_ANR) {
                    String l = logged(exit.getPid());
                    if (l != null) facts.put("logcat", l);
                }
            }
            if (reason == ApplicationExitInfo.REASON_CRASH) {
                Kept k = kept != null ? read(kept) : null;
                return new Report(exit.getTimestamp(), exit.getPid(), k != null ? k.exceptions : one("Crash", description, "generic"), null,
                        k != null && k.stack != null ? k.stack : trace, facts, kept);
            }
            if (reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                String signal = trace != null ? Tombstone.signal(trace) : null;
                if (signal == null) signal = "NativeCrash";
                List<String> frames = trace != null ? Tombstone.frames(trace) : Collections.emptyList();
                String headline = trace != null ? Tombstone.headline(trace) : null;
                return new Report(exit.getTimestamp(), exit.getPid(), one(signal, headline != null ? headline : description, "signalhandler"),
                        fingerprint(signal, frames), trace, facts, null);
            }
            if (reason == ApplicationExitInfo.REASON_ANR) {
                return new Report(exit.getTimestamp(), exit.getPid(), one("ANR", description, "anr"),
                        fingerprint("ANR", trace != null ? mainFrames(trace) : Collections.emptyList()), trace, facts, null);
            }
            String why = killed(reason);
            String memory = "pss " + exit.getPss() / 1024 + " MB, rss " + exit.getRss() / 1024 + " MB";
            List<String> parts = new ArrayList<>();
            for (String s : new String[] {why, description, memory}) if (s != null && !s.isEmpty()) parts.add(s);
            return new Report(exit.getTimestamp(), exit.getPid(), one("Killed", String.join(": ", parts), "generic"), "android:killed:" + why, trace, facts, null);
        } catch (Exception e) {
            return new Report(exit.getTimestamp(), exit.getPid(), new JSONArray(), null, trace, new JSONObject(), kept);
        }
    }

    /** The system WebView's package and version now (as it was at the crash, unless it was updated since). */
    private static String webView() {
        try {
            android.content.pm.PackageInfo p = android.webkit.WebView.getCurrentWebViewPackage();
            return p != null ? p.packageName + " " + p.versionName : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** What an ended process logged last, warnings and up, while the log still has it: its last LOGGED lines, at most
     *  LOGGED_BYTES. */
    private static String logged(int pid) {
        try {
            Process p = new ProcessBuilder("logcat", "-d", "-v", "threadtime", "--pid=" + pid, "*:W").redirectErrorStream(true).start();
            ArrayDeque<String> lines = new ArrayDeque<>();
            try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                for (String l; (l = r.readLine()) != null; ) {
                    lines.addLast(l);
                    if (lines.size() > LOGGED) lines.removeFirst();
                }
            }
            p.waitFor(5, TimeUnit.SECONDS);
            p.destroy();
            StringBuilder b = new StringBuilder();
            for (String l : lines) {
                if (l.startsWith("--------- beginning of")) continue;
                if (b.length() > 0) b.append('\n');
                b.append(l);
            }
            String s = b.length() > LOGGED_BYTES ? b.substring(b.length() - LOGGED_BYTES) : b.toString();
            return s.isEmpty() ? null : s;
        } catch (Exception e) {
            return null;
        }
    }

    private static Report javaOnly(long at, File file) {
        Kept k = read(file);
        JSONObject facts = new JSONObject();
        try {
            facts.put("reason", "crash");
        } catch (Exception ignored) {
        }
        return new Report(at, 0, k != null ? k.exceptions : one("Crash", "", "generic"), null, k != null ? k.stack : null, facts, file);
    }

    private static final class Kept {
        final JSONArray exceptions;
        final String stack;

        Kept(JSONArray exceptions, String stack) {
            this.exceptions = exceptions;
            this.stack = stack;
        }
    }

    private static Kept read(File file) {
        try {
            JSONObject v = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
            return new Kept(v.getJSONArray("exceptions"), v.has("stack") ? v.optString("stack", null) : null);
        } catch (Exception e) {
            return null;
        }
    }

    private static JSONArray one(String type, String value, String mechanism) {
        try {
            JSONObject x = new JSONObject().put("type", type);
            if (!value.isEmpty()) x.put("value", value);
            x.put("mechanism", new JSONObject().put("handled", false).put("synthetic", false).put("type", mechanism));
            return new JSONArray().put(x);
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    /** What makes two native crashes or ANRs the same issue (no frames PostHog reads for them): where they happened. */
    private static String fingerprint(String kind, List<String> frames) {
        if (frames.isEmpty()) return null;
        return "android:" + kind + ":" + String.join("|", frames.subList(0, Math.min(6, frames.size())));
    }

    /** The main thread's top frames in an ANR's dump. */
    static List<String> mainFrames(String dump) {
        List<String> out = new ArrayList<>();
        boolean in = false;
        for (String line : dump.split("\n", -1)) {
            if (!in) {
                if (line.startsWith("\"main\"")) in = true;
                continue;
            }
            if (line.trim().isEmpty()) break;
            String t = line.trim();
            if (!t.startsWith("at ")) continue;
            t = t.substring(3);
            int p = t.indexOf('(');
            out.add(p >= 0 ? t.substring(0, p) : t);
        }
        return out;
    }

    static String iso(long ms) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT);
        f.setTimeZone(TimeZone.getTimeZone("UTC"));
        return f.format(new Date(ms));
    }

    static String take(String s, int n) {
        return s.length() > n ? s.substring(0, n) : s;
    }

    private static byte[] readAtMost(InputStream input, int most) throws java.io.IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[64 * 1024];
        while (out.size() < most) {
            int n = input.read(buf, 0, Math.min(buf.length, most - out.size()));
            if (n < 0) break;
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }
}
