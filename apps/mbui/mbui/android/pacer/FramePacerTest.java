package dev.mbui;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.PriorityQueue;

/**
 * MBView's pacing (FramePacer) on a clock of the test's own: the display's vsyncs on a grid, the main thread's queue
 * and Choreographer's callbacks, the drawing thread's frames (their work), the GPU behind it and the surface's buffers
 * as SurfaceFlinger takes them at the vsyncs (a buffer shown no sooner than the time eglPresentationTimeANDROID said).
 * What the app asks for is said by each run: a motion (every frame asks for the next until it ends), keys struck. The
 * same run gives the same frames on every machine: nothing reads the machine's clock or its threads.
 *
 * What is asserted is what a person sees: while the app asks for a frame at each vsync, each refresh shows a new one
 * (a refresh with none is a stutter), and the surface says the display's highest rate while something moves and while
 * the field is typed into. Run: scripts/framepacer_test.sh.
 */
public final class FramePacerTest {
    // ---- the simulated phone ----

    /** What the app does in a frame built for {@code now} (ms): its work on the drawing thread and the GPU's (ms), and
     * whether it asks for another. */
    interface App {
        double work(int frame, double now);

        double gpu(int frame, double now);

        boolean more(int frame, double now);

        /** The rate what moves on by the clock alone needs, said by the frame (MBView.framesPaced; 0 none): its next
         * woken for, at the vsync before the one that many frames a second on (MBView.wakeAt). */
        default float paced(int frame, double now) {
            return 0;
        }
    }

    static final class Event implements Comparable<Event> {
        final long at;
        final long seq;
        final Runnable run;

        Event(long at, long seq, Runnable run) {
            this.at = at;
            this.seq = seq;
            this.run = run;
        }

        @Override
        public int compareTo(Event o) {
            return at != o.at ? Long.compare(at, o.at) : Long.compare(seq, o.seq);
        }
    }

    static final class Phone implements FramePacer.Platform {
        final long period;
        /** how many buffers SurfaceFlinger's queue holds for the surface, the one shown among them (triple buffering) */
        final int buffers;
        /** whether eglSwapBuffers waits for the frame before's GPU work (a driver that throttles so) */
        final boolean swapWaitsGpu;
        /** how long after requestRender the drawing thread begins the frame (ns) */
        final long wake;
        final FramePacer pacer;
        App app;
        boolean typing;

        long now;
        long seq;
        final PriorityQueue<Event> events = new PriorityQueue<>();
        boolean onMain;
        /** Choreographer's callbacks for the next vsync (posted on the main thread) */
        List<Runnable> nextVsync = new ArrayList<>();
        /** the drawing thread: busy until, its queued events (queueEvent), a frame requested */
        long drawingFree;
        final ArrayDeque<Runnable> drawingQueue = new ArrayDeque<>();
        boolean renderRequested;
        boolean drawingScheduled;
        long gpuFree;
        long gpuLastEnd;
        /** buffers queued and not yet shown: each its ready time and the time it may be shown from */
        final ArrayDeque<long[]> queued = new ArrayDeque<>();
        int frames;
        /** the vsyncs (their index) each showed a new frame at; the app's frames' work (ms), by frame */
        final List<Long> shownAt = new ArrayList<>();
        final List<double[]> drawn = new ArrayList<>();
        /** the rate said, as it changed: (time ns, rate) */
        final List<double[]> rates = new ArrayList<>();
        float rate;

        Phone(double hz, int buffers, boolean swapWaitsGpu, long wake) {
            this.period = Math.round(1e9 / hz);
            this.buffers = buffers;
            this.swapWaitsGpu = swapWaitsGpu;
            this.wake = wake;
            this.pacer = new FramePacer(this);
            pacer.framePeriod = period;
            pacer.topRate = (float) hz;
            // the display's vsyncs, from the first after 0
            at(period, this::vsync);
        }

        void at(long t, Runnable r) {
            events.add(new Event(t, seq++, r));
        }

        void main(long t, Runnable r) {
            at(t, () -> {
                onMain = true;
                r.run();
                onMain = false;
            });
        }

        void runUntil(long end) {
            while (!events.isEmpty() && events.peek().at <= end) {
                Event e = events.poll();
                now = e.at;
                e.run.run();
            }
            now = end;
        }

        /** A vsync: what SurfaceFlinger shows at it, then Choreographer's callbacks on the main thread. */
        void vsync() {
            long v = now;
            // the first buffer queued whose GPU work is done and whose time has come is shown; one a vsync
            if (!queued.isEmpty()) {
                long[] b = queued.peek();
                if (b[0] <= v && b[1] <= v) {
                    queued.poll();
                    shownAt.add(v / period);
                    bufferFreed();
                }
            }
            List<Runnable> cbs = nextVsync;
            nextVsync = new ArrayList<>();
            onMain = true;
            for (Runnable r : cbs) r.run();
            onMain = false;
            at(v + period, this::vsync);
        }

        long vsyncTime() {
            return (now / period) * period;
        }

        // ---- FramePacer.Platform ----

        @Override public long nanoTime() { return now; }

        @Override public boolean onMain() { return onMain; }

        @Override public void postMain(Runnable r) { main(now, r); }

        @Override public void postVsync() {
            // Android 13's: told with its preferred timeline, shown two vsyncs on (the app's frame deadline)
            nextVsync.add(() -> pacer.vsyncCame(vsyncTime(), vsyncTime() + 2 * period));
        }

        @Override public void atNextVsyncOnDrawing(Runnable r) {
            main(now, () -> nextVsync.add(() -> {
                drawingQueue.add(r);
                kickDrawing();
            }));
        }

        @Override public void requestRender() {
            renderRequested = true;
            kickDrawing();
        }

        @Override public boolean setRate(float r) {
            rate = r;
            rates.add(new double[] {now, r});
            return true;
        }

        @Override public boolean typing() { return typing; }

        // ---- the drawing thread ----

        void kickDrawing() {
            if (drawingScheduled || drawingFree == BLOCKED) return;
            if (drawingQueue.isEmpty() && !renderRequested) return;
            drawingScheduled = true;
            at(Math.max(now + wake, drawingFree), this::drawingStep);
        }

        void drawingStep() {
            drawingScheduled = false;
            if (drawingFree > now) {
                kickDrawing();
                return;
            }
            // GLSurfaceView's guarded run: queued events first, then a frame where one is requested
            while (!drawingQueue.isEmpty()) drawingQueue.poll().run();
            if (renderRequested) {
                renderRequested = false;
                drawFrame();
            }
            kickDrawing();
        }

        static final long BLOCKED = Long.MAX_VALUE / 4;

        /** MBView.onDrawFrame's app frame (not a picture alone, not a shot): its work, then eglSwapBuffers. */
        void drawFrame() {
            boolean wantedApp = pacer.appWanted.getAndSet(false), pictured = pacer.picturesOnly.getAndSet(false);
            long[] vat = pacer.vsyncAt();
            if (pictured && !wantedApp) {
                pacer.redrawn();
                return;
            }
            long began = now;
            FramePacer.Begun b = pacer.begin(vat, began);
            int f = frames++;
            double work = app.work(f, b.now);
            boolean more = app.more(f, b.now);
            float paced = app.paced(f, b.now);
            long cpuEnd = began + Math.round(work * 1e6);
            // (the thread busy with it till its work is done: what comes meanwhile, a vsync, comes as it works)
            drawingFree = cpuEnd;
            at(cpuEnd, () -> {
                pacer.ended(more, false, b.following, paced);
                // (paced: woken for at the vsync before the one its rate's frame falls on, as MBView.wakeAt asks)
                if (paced > 0) main(Math.round(b.now * 1e6 + 1e9 / paced) - period, pacer::wantFrame);
                // the GPU draws it after the frame before's; swapped, the buffer is queued
                long gpuStart = Math.max(cpuEnd, gpuFree);
                long gpuEnd = gpuStart + Math.round(app.gpu(f, b.now) * 1e6);
                gpuFree = gpuEnd;
                long swapDone = swapWaitsGpu ? Math.max(cpuEnd, gpuLastEnd) : cpuEnd;
                gpuLastEnd = gpuEnd;
                long showFrom = b.shows != 0 ? b.shows - period / 2 : 0;
                queued.add(new long[] {gpuEnd, showFrom});
                drawn.add(new double[] {b.now, work});
                // (a buffer to draw the next into: the queue holds `buffers`, one of them shown)
                drawingFree = queued.size() >= buffers - 1 ? BLOCKED : swapDone;
                kickDrawing();
            });
        }

        /** A buffer shown frees one: the drawing thread waiting on it goes on. */
        void bufferFreed() {
            if (drawingFree == BLOCKED && queued.size() < buffers - 1) {
                drawingFree = now;
                kickDrawing();
            }
        }
    }

    // ---- runs ----

    /** The refreshes from {@code from} until {@code to} (ns) that showed no new frame (their vsyncs' index). */
    static List<Long> missed(Phone ph, long from, long to) {
        List<Long> out = new ArrayList<>();
        long first = from / ph.period + 1, last = to / ph.period;
        int i = 0;
        for (long k = first; k <= last; k++) {
            while (i < ph.shownAt.size() && ph.shownAt.get(i) < k) i++;
            if (i >= ph.shownAt.size() || ph.shownAt.get(i) != k) out.add(k);
        }
        return out;
    }

    /** A motion from {@code start} for {@code ms}: each frame `work` and `gpu` (ms), asking for the next while it goes. */
    static Phone motion(Phone ph, double startMs, double ms, App app) {
        ph.app = app;
        long start = Math.round(startMs * 1e6);
        ph.main(start, ph.pacer::wantFrame);
        ph.runUntil(start + Math.round((ms + 200) * 1e6));
        return ph;
    }

    static App steady(double work, double gpu, double untilMs) {
        return new App() {
            @Override public double work(int f, double now) { return work; }

            @Override public double gpu(int f, double now) { return gpu; }

            @Override public boolean more(int f, double now) { return now < untilMs; }
        };
    }

    static int failures;

    static void check(String what, boolean ok, String said) {
        System.out.println((ok ? "ok   " : "FAIL ") + what + (said.isEmpty() ? "" : ": " + said));
        if (!ok) failures++;
    }

    /**
     * The known list: what is wrong now and known, run and said every run (KNOWN). Its count `now` is to be the one it
     * was `owed` at when it was found: worse fails, and so does better (mended: bring `owed` down to it, at 0 take it
     * off the list and assert it). The list only gets shorter.
     */
    static void owed(String what, int now, int owed, String said) {
        String verdict = now > owed ? "FAIL (worse) " : now < owed ? "FAIL (better: owed " + owed + " → " + now + ") " : "KNOWN ";
        System.out.println(verdict + what + ": " + now + (said.isEmpty() ? "" : ", " + said));
        if (now != owed) failures++;
    }

    /** A motion of `work` and `gpu` a frame at 120 Hz for a second: the refreshes it left with no new frame. */
    static void motionCase(String what, double work, double gpu, boolean swapWaitsGpu) {
        Phone ph = new Phone(120, 3, swapWaitsGpu, 200_000);
        double start = 100, ms = 1000;
        motion(ph, start, ms, steady(work, gpu, start + ms));
        // (from its third refresh: the first frame is asked for as the motion starts, shown two vsyncs on)
        List<Long> miss = missed(ph, Math.round((start + 4 * 8.34) * 1e6), Math.round((start + ms) * 1e6));
        check(what, miss.isEmpty(), miss.size() + " of " + Math.round(ms / 8.333) + " refreshes with no new frame"
                + (miss.isEmpty() ? "" : ", first at vsync " + miss.get(0)) + "; frames drawn " + ph.drawn.size());
    }

    /** Frames' work as a phone's PERF said it (devperf2: t, work, present ms a line): each run of frames drawn one
     * after another (under 60 ms apart) replayed as a motion, its frames' work theirs, the GPU's `gpu` each. */
    static void replay(String file, double gpu) throws IOException {
        List<double[]> rows = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(file))) {
            for (String line; (line = r.readLine()) != null; ) {
                String[] p = line.trim().split("\\s+");
                if (p.length >= 3) rows.add(new double[] {Double.parseDouble(p[0]), Double.parseDouble(p[1]), Double.parseDouble(p[2])});
            }
        }
        // runs of frames each under 60 ms after the one before
        int totalRefreshes = 0, totalMissed = 0, cheapMissed = 0, phoneMissed = 0, phoneCheap = 0;
        int i = 0;
        while (i < rows.size()) {
            int j = i + 1;
            while (j < rows.size() && rows.get(j)[0] - rows.get(j - 1)[0] < 60) j++;
            if (j - i >= 10) {
                for (int k = i + 1; k < j; k++) {
                    double d = rows.get(k)[0] - rows.get(k - 1)[0];
                    if (d > 12) {
                        phoneMissed++;
                        if (rows.get(k - 1)[1] + rows.get(k - 1)[2] < 4) phoneCheap++;
                    }
                }
                double[] work = new double[j - i];
                for (int k = i; k < j; k++) work[k - i] = rows.get(k)[1] + rows.get(k)[2];
                double ms = rows.get(j - 1)[0] - rows.get(i)[0];
                Phone ph = new Phone(120, 3, true, 200_000);
                double start = 100;
                motion(ph, start, ms, new App() {
                    @Override public double work(int f, double now) { return work[Math.min(f, work.length - 1)]; }

                    @Override public double gpu(int f, double now) { return gpu; }

                    @Override public boolean more(int f, double now) { return now < start + ms; }
                });
                List<Long> miss = missed(ph, Math.round((start + 4 * 8.34) * 1e6), Math.round((start + ms) * 1e6));
                totalRefreshes += (int) Math.round(ms / 8.333);
                totalMissed += miss.size();
                // of those, the frame drawn before it took under 4 ms
                for (long k : miss) {
                    double before = 0;
                    for (double[] dr : ph.drawn) if (dr[0] * 1e6 < k * ph.period) before = dr[1];
                    if (before < 4) cheapMissed++;
                }
            }
            i = j;
        }
        owed("devperf2's frames replayed, GPU " + gpu + " ms a frame: refreshes with no new frame after a frame under 4 ms",
                cheapMissed, gpu <= 1 ? 1 : 5, totalMissed + " of " + totalRefreshes + " with none at all (the phone: "
                        + phoneMissed + ", " + phoneCheap + " after one under 4 ms)");
    }

    /** Keys struck into the field every `every` ms (no motion of the app's): the rate said for each key's frame. */
    static void typingCase() {
        Phone ph = new Phone(120, 3, true, 200_000);
        ph.typing = true;
        ph.app = steady(1.0, 1.0, -1);
        ph.main(Math.round(50e6), ph.pacer::typingChanged);
        for (int k = 0; k < 10; k++) ph.main(Math.round((100 + 120 * k) * 1e6), ph.pacer::wantFrame);
        ph.runUntil(Math.round(1400e6));
        check("typing: the display's highest rate said while the field is typed into", ph.rate == 120f,
                "rate " + ph.rate + ", said " + ph.rates.size() + " times");
    }

    /** After a motion: the rate kept for a second (the next flick does not climb back to it), then let go. */
    static void rateAfterMotion() {
        Phone ph = new Phone(120, 3, true, 200_000);
        motion(ph, 100, 300, steady(1.0, 1.0, 400));
        float during = ph.rate;
        ph.runUntil(Math.round((400 + 900) * 1e6));
        float soon = ph.rate;
        ph.runUntil(Math.round((400 + 1300) * 1e6));
        check("a motion's rate: the highest while it moves, kept a second after it", during == 120f && soon == 120f,
                "moving " + during + ", 0.9 s after " + soon);
        // (2026-11-05: a motion whose last frame followed the one before (FramePacer.ended's `following`) said the rate
        // again and never counted down to letting it go; with no frame after it the display stays at its highest)
        owed("a motion's rate let go 1.3 s after it: the display still at its highest", ph.rate == 0f ? 0 : 1, 1,
                "1.3 s after " + ph.rate);
    }

    /** A spinner whose frames say they need 30 a second (frame_pace.mbt): that rate said, and as many frames drawn. */
    static void pacedCase() {
        Phone ph = new Phone(120, 3, true, 200_000);
        ph.app = new App() {
            @Override public double work(int f, double now) { return 1; }

            @Override public double gpu(int f, double now) { return 1; }

            @Override public boolean more(int f, double now) { return false; }

            @Override public float paced(int f, double now) { return now < 1100 ? 30 : 0; }
        };
        ph.main(Math.round(100e6), ph.pacer::wantFrame);
        ph.runUntil(Math.round(1050e6));
        float during = ph.rate;
        int frames = ph.drawn.size();
        check("a motion paced at 30 Hz: that rate said of the display, about 30 frames a second drawn",
                during == 30f && frames >= 28 && frames <= 30, "rate " + during + ", " + frames + " frames in 0.95 s");
    }

    public static void main(String[] args) throws IOException {
        motionCase("a motion of 1 ms CPU and 1 ms GPU a frame shows a new frame at every refresh", 1, 1, true);
        motionCase("a motion of 0.5 ms CPU and 7 ms GPU a frame (the GPU under a refresh) shows a new frame at every refresh", 0.5, 7, true);
        motionCase("the same, a driver whose swap does not wait for the GPU", 0.5, 7, false);
        motionCase("a motion of 6 ms CPU and 1 ms GPU a frame shows a new frame at every refresh", 6, 1, true);
        typingCase();
        rateAfterMotion();
        pacedCase();
        if (args.length > 0) {
            replay(args[0], 1);
            replay(args[0], 7);
        }
        if (failures > 0) {
            System.out.println(failures + " failed");
            System.exit(1);
        }
    }
}
