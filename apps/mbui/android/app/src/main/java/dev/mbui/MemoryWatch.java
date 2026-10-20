package dev.mbui;

import android.content.Context;
import android.os.Debug;
import android.os.FileObserver;
import android.os.SystemClock;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * The app's memory running away, told from inside, as still.fail's Android app does (MemoryWatch.kt; docs/telemetry.md
 * → 安卓): on an OPPO PLP110 in 2026-10 the native heap grew some 300 MB a minute until the system killed the app, with
 * the Rust shell's threads busy while the app sat still. Once the native heap passes {@link #LIMIT}, what is under way
 * then goes to PostHog once per process as {@code MemoryRunaway}: the shell's calls by operation over a short window,
 * the core's JS sampled for that window (its hottest stacks), the busiest threads, and the heap's sizes.
 */
final class MemoryWatch {
    private MemoryWatch() {}

    /** The native heap past which the app reports. */
    private static final long LIMIT = 1536L * 1024 * 1024;
    private static final long EVERY_MS = 30_000L;
    /** How long the calls are counted and the JS sampled. */
    private static final int WINDOW_S = 15;
    /** The longest the sampling is waited for: a trace not written by then (no engine) is a failed one. */
    private static final int UNTIL_S = WINDOW_S + 60;

    private static volatile boolean started;

    static void start(Context context) {
        if (started) return;
        started = true;
        Context app = context.getApplicationContext();
        Thread t = new Thread(() -> {
            try {
                while (Debug.getNativeHeapAllocatedSize() < LIMIT) Thread.sleep(EVERY_MS);
                // Not looked at (the JS sampled for nothing) when reports are turned off (Crashes.reporting).
                if (Crashes.reporting(app)) {
                    Object[] found = look(app);
                    Crashes.memoryRunaway(app, (String) found[0], (JSONObject) found[1]);
                }
            } catch (Throwable ignored) {
            }
        }, "stillfail-memory");
        t.setDaemon(true);
        t.setPriority(Thread.MIN_PRIORITY);
        t.start();
    }

    private static long mb(long b) {
        return b / (1024 * 1024);
    }

    /** What is under way, over WINDOW_S seconds: the report's value and its facts. */
    private static Object[] look(Context context) throws Exception {
        long heapBefore = Debug.getNativeHeapAllocatedSize();
        Map<String, Long> callsBefore = calls(stats());
        Map<String, Object[]> ticksBefore = threadTicks();
        File trace = new File(context.getCacheDir(), "memory-runaway.cpuprofile");
        trace.delete();
        long began = SystemClock.elapsedRealtime();
        // the window is the sampling's: over when its trace is written and closed (the engine writes it once, after
        // WINDOW_S: engine.cpp profile); waited at most UNTIL, a sampling that never ends (no engine yet) counted so
        CountDownLatch written = new CountDownLatch(1);
        FileObserver closed = new FileObserver(trace.getParentFile(), FileObserver.CLOSE_WRITE) {
            @Override
            public void onEvent(int event, String path) {
                if (trace.getName().equals(path)) written.countDown();
            }
        };
        closed.startWatching();
        try {
            CoreProfile.sample(WINDOW_S, trace.getPath());
            written.await(UNTIL_S, TimeUnit.SECONDS);
        } catch (Throwable ignored) {
        } finally {
            closed.stopWatching();
        }
        long ms = Math.max(1, SystemClock.elapsedRealtime() - began);
        long heapAfter = Debug.getNativeHeapAllocatedSize();
        JSONObject stats = stats();
        Map<String, Long> callsAfter = calls(stats);
        Map<String, Object[]> ticksAfter = threadTicks();
        long grew = (heapAfter - heapBefore) * 60_000 / ms;
        List<Map.Entry<String, Long>> busiest = new ArrayList<>();
        for (Map.Entry<String, Long> e : callsAfter.entrySet()) {
            long d = e.getValue() - callsBefore.getOrDefault(e.getKey(), 0L);
            if (d > 0) busiest.add(new java.util.AbstractMap.SimpleEntry<>(e.getKey(), d));
        }
        busiest.sort((a, b) -> Long.compare(b.getValue(), a.getValue()));
        if (busiest.size() > 15) busiest = busiest.subList(0, 15);
        JSONObject hot = null;
        try {
            hot = hottest(new String(Files.readAllBytes(trace.toPath()), StandardCharsets.UTF_8));
        } catch (Exception ignored) {
        }
        trace.delete();
        JSONObject facts = new JSONObject();
        facts.put("native_heap_mb", mb(heapAfter));
        facts.put("native_heap_grew_mb_per_min", mb(grew));
        facts.put("java_heap_mb", mb(Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()));
        facts.put("window_s", WINDOW_S);
        JSONObject sc = new JSONObject();
        for (Map.Entry<String, Long> e : busiest) sc.put(e.getKey(), e.getValue());
        facts.put("shell_calls", sc);
        // Since the process started: a burst before the window (links opened over and over) shows here.
        List<Map.Entry<String, Long>> total = new ArrayList<>(callsAfter.entrySet());
        total.sort((a, b) -> Long.compare(b.getValue(), a.getValue()));
        JSONObject st = new JSONObject();
        for (int i = 0; i < total.size() && i < 20; i++) st.put(total.get(i).getKey(), total.get(i).getValue());
        facts.put("shell_calls_total", st);
        JSONObject open = new JSONObject();
        JSONObject cs = stats != null ? stats.optJSONObject("calls") : null;
        if (cs != null) {
            List<Map.Entry<String, Long>> un = new ArrayList<>();
            for (Iterator<String> k = cs.keys(); k.hasNext(); ) {
                String op = k.next();
                JSONArray v = cs.optJSONArray(op);
                long n = v != null ? v.optLong(1, 0) : 0;
                if (n > 0) un.add(new java.util.AbstractMap.SimpleEntry<>(op, n));
            }
            un.sort((a, b) -> Long.compare(b.getValue(), a.getValue()));
            for (int i = 0; i < un.size() && i < 15; i++) open.put(un.get(i).getKey(), un.get(i).getValue());
        }
        facts.put("shell_unanswered", open);
        if (stats != null && stats.has("handles")) facts.put("shell_handles", stats.get("handles"));
        if (stats != null && stats.has("sqls")) facts.put("shell_sqls", stats.get("sqls"));
        // Each thread's share of one core over the window, in percent (its ticks are 10 ms).
        List<Object[]> used = new ArrayList<>();
        for (Map.Entry<String, Object[]> e : ticksAfter.entrySet()) {
            Object[] before = ticksBefore.get(e.getKey());
            long d = (Long) e.getValue()[1] - (before != null ? (Long) before[1] : 0L);
            used.add(new Object[] {e.getValue()[0], d});
        }
        used.sort((a, b) -> Long.compare((Long) b[1], (Long) a[1]));
        JSONObject threads = new JSONObject();
        for (int i = 0; i < used.size() && i < 8; i++) threads.put((String) used.get(i)[0], (Long) used.get(i)[1] * 1000 / ms);
        facts.put("threads", threads);
        if (hot != null) facts.put("js", hot);
        StringBuilder top = new StringBuilder();
        for (int i = 0; i < busiest.size() && i < 3; i++) {
            if (i > 0) top.append(", ");
            top.append(busiest.get(i).getKey()).append(" ×").append(busiest.get(i).getValue());
        }
        String value = "native heap " + mb(heapAfter) + " MB, +" + mb(grew) + " MB/min; shell: " + (top.length() == 0 ? "quiet" : top);
        return new Object[] {value, facts};
    }

    private static JSONObject stats() {
        try {
            return new JSONObject(CoreProfile.shellStats());
        } catch (Throwable e) {
            return null;
        }
    }

    private static Map<String, Long> calls(JSONObject stats) {
        Map<String, Long> out = new HashMap<>();
        JSONObject cs = stats != null ? stats.optJSONObject("calls") : null;
        if (cs == null) return out;
        for (Iterator<String> k = cs.keys(); k.hasNext(); ) {
            String op = k.next();
            JSONArray v = cs.optJSONArray(op);
            if (v != null) out.put(op, v.optLong(0, 0));
        }
        return out;
    }

    /** Each thread of this process, by its id: its name and the CPU it has used (user and system, ticks of 10 ms). */
    private static Map<String, Object[]> threadTicks() {
        Map<String, Object[]> out = new HashMap<>();
        File[] tasks = new File("/proc/self/task").listFiles();
        if (tasks == null) return out;
        for (File task : tasks) {
            try {
                String stat = new String(Files.readAllBytes(new File(task, "stat").toPath()), StandardCharsets.UTF_8);
                String name = stat.substring(stat.indexOf('(') + 1, stat.lastIndexOf(')'));
                String[] rest = stat.substring(stat.lastIndexOf(')') + 2).split(" ");
                // After the name: state is field 3, utime 14 and stime 15.
                out.put(task.getName(), new Object[] {name + "/" + task.getName(), Long.parseLong(rest[11]) + Long.parseLong(rest[12])});
            } catch (Exception ignored) {
            }
        }
        return out;
    }

    /**
     * The JS sampled (Hermes' trace: {@code stackFrames} by id with their {@code parent}, {@code samples} naming the
     * frame they were in): the share of samples not idle, the functions most in them, and the stacks most sampled. A
     * function is named with where it starts in the core's bundle ({@code name@line:column}).
     */
    static JSONObject hottest(String text) throws Exception {
        JSONObject trace = new JSONObject(text);
        JSONObject frames = trace.getJSONObject("stackFrames");
        JSONArray samples = trace.getJSONArray("samples");
        Map<String, Integer> inclusive = new HashMap<>();
        Map<String, Integer> stacks = new HashMap<>();
        int busy = 0;
        for (int s = 0; s < samples.length(); s++) {
            JSONObject sample = samples.optJSONObject(s);
            String id = sample != null && sample.has("sf") ? sample.get("sf").toString() : null;
            List<String> names = new ArrayList<>();
            while (id != null) {
                JSONObject frame = frames.optJSONObject(id);
                if (frame == null) break;
                names.add(shortName(frame));
                id = frame.has("parent") ? frame.get("parent").toString() : null;
            }
            List<String> real = new ArrayList<>();
            for (String n : names) if (!n.equals("[root]")) real.add(n);
            if (real.isEmpty()) continue;
            busy++;
            for (String n : new HashSet<>(real)) inclusive.merge(n, 1, Integer::sum);
            String key = String.join(" < ", real.subList(0, Math.min(12, real.size())));
            stacks.merge(key, 1, Integer::sum);
        }
        int all = Math.max(1, samples.length());
        JSONObject out = new JSONObject();
        out.put("busy_percent", busy * 100 / all);
        List<Map.Entry<String, Integer>> fs = new ArrayList<>(inclusive.entrySet());
        fs.sort((a, b) -> b.getValue() - a.getValue());
        JSONObject functions = new JSONObject();
        for (int i = 0; i < fs.size() && i < 25; i++) functions.put(fs.get(i).getKey(), fs.get(i).getValue() * 100 / all);
        out.put("functions", functions);
        List<Map.Entry<String, Integer>> ss = new ArrayList<>(stacks.entrySet());
        ss.sort((a, b) -> b.getValue() - a.getValue());
        JSONArray top = new JSONArray();
        for (int i = 0; i < ss.size() && i < 8; i++) top.put(new JSONObject().put("percent", ss.get(i).getValue() * 100 / all).put("stack", ss.get(i).getKey()));
        out.put("stacks", top);
        return out;
    }

    private static String shortName(JSONObject frame) {
        String name = frame.optString("name", "");
        int p = name.indexOf('(');
        if (p >= 0) name = name.substring(0, p);
        if (name.isEmpty()) name = "(anonymous)";
        if (frame.has("funcLine")) return name + "@" + frame.opt("funcLine") + ":" + frame.opt("funcColumn");
        return name;
    }
}
