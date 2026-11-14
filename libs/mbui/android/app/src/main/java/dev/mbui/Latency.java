package dev.mbui;

import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Random;

/**
 * How long input takes to show on this phone's screen (a drive's {@code latency MODE TEXT}, Host.drive 12;
 * still.fail's scripts/latency.sh): from when an event arrives to when the frame showing it was presented by the
 * display, as the system says of the frame (EGL_ANDROID_get_frame_timestamps' display present time,
 * android_host.c's latencyFrame). mbui's src/host/mac_latency.h is the Mac's, and says why runs are compared by their
 * medians. For people to read, never a check's condition.
 *
 * <p>Events come from a thread of their own at any time within a refresh, posted to the main thread as the system's
 * come there, and go to the view as the system's do: {@code type} a character committed by the input method (the view's
 * InputConnection, as Host.drive's), a key every 60 to 140 ms; {@code scroll} a finger down at the point, 60 moves of
 * 3 points every 4 to 12 ms one way, lifted (what it flings after drawn too), the next gesture the other way; {@code
 * drag} the same held, 30 moves up and 30 down, lifted where it went down; {@code anim} no input. An event is taken to
 * arrive as it is posted. The frame showing it is the first the drawing thread begins after the app took it there (MBView
 * hands each input to that thread). Its parts: waiting for the main thread (queue), handling it there (handle), to the
 * app's handling on the drawing thread and through it (gl), to the frame's start (tick: the vsync asked for), the frame
 * (build: built, laid out, painted, drawn), from its swap to the compositor's latch (latch: the GPU, the presentation
 * time MBView gives it), and to the display (screen). Of the frames: what share of the refreshes from the first frame
 * shown to the last showed a new one, and how many never showed. One line, "LATENCY …", on the log; then the app ends.
 */
final class Latency {
    private Latency() {}

    private static final class Ev {
        long arrived, handling, handled, gl;
        int frame = -1;
        boolean measured;
    }

    private static final class Fr {
        long start, end, id;
        /** rendering complete, latch, first composition, display present (ns; -1 none, -2 not yet) */
        final long[] t = {-2, -2, -2, -2};
        boolean measured, settled;
    }

    private static final ArrayList<Ev> events = new ArrayList<>();
    private static final ArrayList<Fr> frames = new ArrayList<>();
    private static int framed;  // the events up to here have their frame (or will have none)
    private static volatile boolean running, measuring;
    private static long frameStart;
    private static String mode;
    private static float x, y;  // pixels
    private static final Random random = new Random();

    /** The drive's "MODE X Y" (the app's points): the run started; false where it is not one. */
    static int start(String text) {
        String[] w = text.split(" ");
        MBView v = Host.view;
        if (running || v == null || w.length != 3) return 0;
        if (!Arrays.asList("type", "scroll", "drag", "anim").contains(w[0])) return 0;
        mode = w[0];
        x = Float.parseFloat(w[1]) * v.density;
        y = Float.parseFloat(w[2]) * v.density;
        running = true;
        Thread t = new Thread(Latency::run, "latency");
        t.start();
        return 1;
    }

    /** A frame begins (the drawing thread, MBView.onDrawFrame). */
    static void frameBegins() {
        if (running) frameStart = System.nanoTime();
    }

    /** It is drawn, its swap next (the drawing thread): the events taken before it began are its. */
    static void frameEnds() {
        if (!running) return;
        Fr f = new Fr();
        f.start = frameStart;
        f.end = System.nanoTime();
        f.id = Native.latencyFrame();
        f.measured = measuring;
        synchronized (Latency.class) {
            int k = frames.size();
            frames.add(f);
            while (framed < events.size()) {
                Ev e = events.get(framed);
                if (e.gl == 0 || e.gl > f.start) break;
                e.frame = k;
                framed++;
            }
        }
        settle(false);
    }

    /**
     * What the system says of the frames not settled yet (the drawing thread): a frame is settled once its display
     * present is said, or none comes (the frame never shown, or no longer kept: {@code all}, as the run ends).
     */
    private static void settle(boolean all) {
        long[] t = new long[4];
        synchronized (Latency.class) {
            for (int i = Math.max(0, frames.size() - 64); i < frames.size(); i++) {
                Fr f = frames.get(i);
                if (f.settled) continue;
                if (f.id < 0) {
                    f.settled = true;
                    continue;
                }
                if (Native.latencyTimes(f.id, t) == 0) {
                    if (all || i < frames.size() - 8) f.settled = true;
                    continue;
                }
                System.arraycopy(t, 0, f.t, 0, 4);
                if (t[3] != -2 || all) f.settled = true;
            }
        }
    }

    private static void inject(Runnable r) {
        final Ev e = new Ev();
        e.arrived = System.nanoTime();
        e.measured = measuring;
        Host.main.post(() -> {
            MBView v = Host.view;
            if (v == null) return;
            e.handling = System.nanoTime();
            r.run();
            e.handled = System.nanoTime();
            synchronized (Latency.class) {
                events.add(e);
            }
            // (after what the handling handed the drawing thread)
            v.queueEvent(() -> e.gl = System.nanoTime());
        });
    }

    private static void onMain(Runnable r) {
        final Object done = new Object();
        final boolean[] ran = {false};
        Host.main.post(() -> {
            r.run();
            synchronized (done) {
                ran[0] = true;
                done.notify();
            }
        });
        synchronized (done) {
            while (!ran[0]) {
                try {
                    done.wait();
                } catch (InterruptedException ignored) {
                    return;
                }
            }
        }
    }

    private static void sleepMs(double ms) {
        try {
            Thread.sleep((long) ms, (int) ((ms - (long) ms) * 1e6));
        } catch (InterruptedException ignored) {
        }
    }

    private static double between(double lo, double hi) {
        return lo + random.nextDouble() * (hi - lo);
    }

    private static long down;

    private static void touch(int action, float px, float py) {
        MBView v = Host.view;
        if (v == null) return;
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN) down = now;
        MotionEvent e = MotionEvent.obtain(down, now, action, px, py, 0);
        e.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        v.dispatchTouchEvent(e);
        e.recycle();
    }

    private static int n, events0, warmup0;

    private static boolean next() {
        if (n == warmup0) measuring = true;
        n++;
        return n <= warmup0 + events0;
    }

    private static int envInt(String name, int dflt) {
        String v = System.getenv(name);
        try {
            return v == null || v.isEmpty() ? dflt : Integer.parseInt(v);
        } catch (NumberFormatException e) {
            return dflt;
        }
    }

    private static void run() {
        events0 = envInt("MBUI_LATENCY_EVENTS", 300);
        warmup0 = envInt("MBUI_LATENCY_WARMUP", 30);
        MBView v = Host.view;
        float refresh = v != null && v.getDisplay() != null ? v.getDisplay().getRefreshRate() : 60;
        float step = 3 * (v != null ? v.density : 1);
        // (the frames of what the step set off, at full speed first)
        sleepMs(1000);
        switch (mode) {
            case "type": {
                String words = "the quick brown fox jumps over the lazy dog ";
                while (next()) {
                    String c = String.valueOf(words.charAt(n % words.length()));
                    inject(() -> Script.ic(Host.view).commitText(c, 1));
                    sleepMs(between(60, 140));
                }
                break;
            }
            case "scroll":
            case "drag": {
                int way = -1;
                while (n < warmup0 + events0) {
                    onMain(() -> touch(MotionEvent.ACTION_DOWN, x, y));
                    float py = y;
                    for (int i = 0; i < 60 && next(); i++) {
                        py += mode.equals("scroll") ? way * step : (i < 30 ? -step : step);
                        final float at = py;
                        inject(() -> touch(MotionEvent.ACTION_MOVE, x, at));
                        sleepMs(between(4, 12));
                    }
                    final float end = py;
                    onMain(() -> touch(MotionEvent.ACTION_UP, x, end));
                    way = -way;
                    sleepMs(mode.equals("scroll") ? 600 : 300);
                }
                break;
            }
            default:
                sleepMs(warmup0 * 1000.0 / refresh);
                measuring = true;
                sleepMs(events0 * 1000.0 / refresh);
        }
        // (the last frames reach the screen, and what the system says of them is read)
        sleepMs(300);
        measuring = false;
        if (v != null) {
            Host.requestFrame();
            sleepMs(200);
            final Object done = new Object();
            final boolean[] ran = {false};
            v.queueEvent(() -> {
                settle(true);
                synchronized (done) {
                    ran[0] = true;
                    done.notify();
                }
            });
            synchronized (done) {
                while (!ran[0]) {
                    try {
                        done.wait();
                    } catch (InterruptedException ignored) {
                        break;
                    }
                }
            }
        }
        Host.log(report(refresh));
        Host.exit(0);
    }

    private static double ms(long ns) {
        return ns / 1e6;
    }

    private static String report(float refresh) {
        synchronized (Latency.class) {
            // (MBUI_LATENCY_SAY=1: the first frames as the system told them, for a run whose frames never show)
            if ("1".equals(System.getenv("MBUI_LATENCY_SAY")))
                for (int i = 0; i < Math.min(8, frames.size()); i++) {
                    Fr f = frames.get(i);
                    Host.log("LATENCY frame " + f.id + " end " + f.end + " times " + Arrays.toString(f.t));
                }
            int nfr = 0, notShown = 0;
            ArrayList<Long> shown = new ArrayList<>();
            for (Fr f : frames) {
                if (!f.measured) continue;
                nfr++;
                if (f.t[3] > 0) shown.add(f.t[3]);
                else notShown++;
            }
            double[] parts = new double[7];  // queue, handle, gl, tick, build, latch, screen
            double[] total = new double[events.size()];
            int k = 0;
            for (Ev e : events) {
                if (!e.measured || e.frame < 0) continue;
                Fr f = frames.get(e.frame);
                if (f.t[3] <= 0 || f.t[1] <= 0) continue;
                long start = Math.max(f.start, e.gl);
                long[] at = {e.arrived, e.handling, e.handled, e.gl, start, f.end, f.t[1], f.t[3]};
                for (int i = 0; i < 7; i++) parts[i] += ms(at[i + 1] - at[i]);
                total[k++] = ms(f.t[3] - e.arrived);
            }
            double[] t = Arrays.copyOf(total, k);
            Arrays.sort(t);
            double mean = 0;
            for (double d : t) mean += d;
            double newShare = 0;
            if (shown.size() > 1) {
                java.util.Collections.sort(shown);
                java.util.HashSet<Long> refreshes = new java.util.HashSet<>();
                for (long s : shown) refreshes.add(Math.round(s / 1e9 * refresh));
                long span = Math.round((shown.get(shown.size() - 1) - shown.get(0)) / 1e9 * refresh) + 1;
                newShare = 100.0 * refreshes.size() / span;
            }
            double d = Math.max(k, 1);
            return String.format(java.util.Locale.ROOT,
                    "LATENCY mode=%s refresh=%.0f events=%d mean=%.3f p50=%.3f p90=%.3f p99=%.3f queue=%.3f handle=%.3f "
                            + "gl=%.3f tick=%.3f build=%.3f latch=%.3f screen=%.3f frames=%d new=%.2f notshown=%.2f posted=%d",
                    mode, refresh, k, mean / d, pct(t, .5), pct(t, .9), pct(t, .99), parts[0] / d, parts[1] / d,
                    parts[2] / d, parts[3] / d, parts[4] / d, parts[5] / d, parts[6] / d, nfr,
                    newShare, nfr > 0 ? 100.0 * notShown / nfr : 0, events.size());
        }
    }

    private static double pct(double[] sorted, double p) {
        return sorted.length == 0 ? 0 : sorted[(int) (p * (sorted.length - 1))];
    }
}
