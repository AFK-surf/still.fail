package dev.mbui;

import android.content.Context;
import android.opengl.GLSurfaceView;
import android.os.Looper;
import android.icu.text.BreakIterator;
import android.text.Editable;
import android.text.InputType;
import android.text.Selection;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ViewTreeObserver;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.util.ArrayDeque;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * The surface the MoonBit app draws on. Everything MoonBit runs on the GL
 * thread: frames there, and input is queued onto it. Frames are paced by the
 * display's vsync (Choreographer), one per vsync at most, each told that
 * vsync's time, as Compose's frames are: a frame asked for while touches are
 * handled (the input phase of a vsync) is drawn at that vsync, one asked for
 * by a frame (an animation) at the next; the system's back, said in a vsync's
 * animation phase, is drawn by the next (back()).
 */
public class MBView extends GLSurfaceView implements GLSurfaceView.Renderer {
    private static boolean started;  // MoonBit's main runs once per process
    /**
     * Whose GL context the host's drawing (its programs, textures, atlas: android_host.c) was last set up in: a count,
     * each view's own set when it set it up. Two views (MainActivity's and an OverActivity's) each have a context of
     * their own; one drawn after the other set it up in its own sets it up again in its own first.
     */
    private static int setUp;
    private int mine;
    final float density;

    public MBView(Context c) {
        super(c);
        density = c.getResources().getDisplayMetrics().density;
        setEGLContextClientVersion(3);
        setEGLConfigChooser(8, 8, 8, 8, 0, 0);
        // On top of the window, translucent: the app over another app (OverActivity) draws over that app, nothing of
        // its own ground; native views (NativeViews: a player, a page) are drawn in it, by their pictures.
        getHolder().setFormat(android.graphics.PixelFormat.TRANSLUCENT);
        setZOrderOnTop(true);
        setPreserveEGLContextOnPause(true);
        setRenderer(this);
        setRenderMode(RENDERMODE_WHEN_DIRTY);
        setFocusable(true);
        setFocusableInTouchMode(true);
        // a screen reader turned on or off: the app tells its widgets, or stops (A11y, @hostapi.a11y_on)
        android.view.accessibility.AccessibilityManager am =
                (android.view.accessibility.AccessibilityManager) c.getSystemService(Context.ACCESSIBILITY_SERVICE);
        if (am != null) am.addAccessibilityStateChangeListener(on -> wantFrame());
    }

    /** The app's widgets for Android's accessibility (A11y): made as the app first tells them. */
    private A11y a11y;

    A11y a11y() {
        if (a11y == null) a11y = new A11y(this);
        return a11y;
    }

    @Override
    public android.view.accessibility.AccessibilityNodeProvider getAccessibilityNodeProvider() {
        return a11y != null && a11y.any() ? a11y : super.getAccessibilityNodeProvider();
    }

    @Override
    protected boolean dispatchHoverEvent(android.view.MotionEvent e) {
        // a finger exploring the screen with a screen reader on: the widget under it (A11y)
        if (a11y != null && a11y.any() && a11y.hover(e)) return true;
        return super.dispatchHoverEvent(e);
    }

    /** A login form of a site the app asks the autofill service for, while it does (Autofills); none else. */
    @Override
    public void onProvideAutofillVirtualStructure(android.view.ViewStructure structure, int flags) {
        Autofills.provide(this, structure);
    }

    /** The login the autofill service filled into that form (Autofills). */
    @Override
    public void autofill(android.util.SparseArray<android.view.autofill.AutofillValue> values) {
        Autofills.filled(values);
    }

    // ---- its surface (main thread) ----

    /** Its surface made: the streams' layers (StreamLayer) put under it, where it is the host's. */
    @Override
    public void surfaceCreated(android.view.SurfaceHolder holder) {
        super.surfaceCreated(holder);
        if (Host.view == this) StreamLayer.parentFrom(this);
    }

    /** Its surface gone: the streams' layers off the screen with it (kept, to be put under the next). */
    @Override
    public void surfaceDestroyed(android.view.SurfaceHolder holder) {
        StreamLayer.parentGone(this);
        super.surfaceDestroyed(holder);
    }

    // ---- GL thread ----

    @Override
    public void onSurfaceCreated(GL10 gl, EGLConfig config) {
        drawingThread();
        Native.surfaceCreated();
        MBText.reset();
        mine = ++setUp;
        if (!started) {
            started = true;
            // (a run to a declared moment: the app's clock is its frames' from the start, shotFrame below)
            if (Host.shotAt >= 0) Native.ownClock();
            Native.start();
        }
    }

    @Override
    public void onSurfaceChanged(GL10 gl, int w, int h) {
        // (a new surface, told after it is made, or the same at another size: whatever was said of the rate, nothing said)
        sayRate(false);
        Native.resize(w, h);
    }

    private double lastFrame;
    // the frame before's vsync (0: none, or it had none), and whether it asked for this one (askAhead: the vsync after
    // its own, or where its work went past that one, the first after its work)
    private long lastVsync;
    private boolean askedAtEnd;

    // A picture at a declared moment (Host.shotAt, --ei shot_at MS: scripts/shots.sh android): the run's frames are on
    // a clock of their own, 1/60 s a frame from 0, as a stable run's on macOS (mac_app.m) and the browser's
    // (web/host.js shot_at), each drawn at the next vsync whether the app asks for it or not, until that clock reaches
    // MS; that frame drawn, no other ("SHOT n t" on the log: adb's screencap takes it), and a frame the system asks
    // for after it drawn at the same moment. The clock stands still while the app awaits the host (an image decoding:
    // what its last frame said), so the picture is of the app at MS on its own clock, however fast the machine is.
    // Never "once the app is at rest": that is settling by another name (a moment is declared, or a drive waits for the
    // page's own named event).
    private double shotClock;
    private int shotFrames;
    private volatile boolean shotTaken;

    private void shotFrame(float w, float h) {
        double t = shotClock;
        takeBacks(Long.MAX_VALUE);
        Native.frame(w, h, density, t, 0);
        // (a run to a moment: the native views' frames put where they show at once)
        NativeViews.framed(false);
        Script.frameDrawn();
        if (shotTaken) return;
        shotFrames++;
        // (the run's way to its moment said every half second of its clock: a machine drawing slowly, the emulator's
        // software renderer on a runner's CPU, is told from one that stopped by these, not by how long it took)
        if (shotFrames % 30 == 0) Host.log("shot: frame " + shotFrames + " at " + t);
        if (Native.awaiting() > 0) {
            // the clock stands still; the host's answer asks for the next frame
            return;
        }
        if (t >= Host.shotAt) {
            shotTaken = true;
            // said once it is on the screen: swapped as this returns, taken by the compositor at the next vsync,
            // shown by the one after
            final String said = "SHOT " + shotFrames + " " + t;
            // (and not before the window is the one shown: the system's starting window, its splash, is over the
            // app's until the app's has drawn and taken the focus, a picture as early as the first frame would be of
            // the splash; and the system fades that out after it, so a picture is taken once its window is gone too:
            // scripts/android.sh shown)
            Runnable say = () -> Choreographer.getInstance().postFrameCallback(a ->
                    Choreographer.getInstance().postFrameCallback(b -> Host.log(said)));
            Host.main.post(() -> {
                if (hasWindowFocus()) {
                    say.run();
                    return;
                }
                // (said, so a picture that never comes is told by what it waits for)
                Host.log("shot: " + said.substring(5) + " waits for the window's focus");
                getViewTreeObserver().addOnWindowFocusChangeListener(new ViewTreeObserver.OnWindowFocusChangeListener() {
                    @Override
                    public void onWindowFocusChanged(boolean focused) {
                        if (!focused) return;
                        getViewTreeObserver().removeOnWindowFocusChangeListener(this);
                        say.run();
                    }
                });
            });
            return;
        }
        shotClock = shotFrames * (1000.0 / 60.0);
        wantFrame();
    }

    @Override
    public void onDrawFrame(GL10 gl) {
        // a view not the host's (its activity paused under another of the app's: an OverActivity's draws), kept as it
        // last drew: one thread draws the app at a time
        if (Host.view != this) return;
        boolean app = appWanted.getAndSet(false), pictured = picturesOnly.getAndSet(false);
        // another view set the drawing up in its own context since this one did (an OverActivity came and went): set
        // up again here, at this view's size
        if (mine != setUp) {
            Native.surfaceCreated();
            MBText.reset();
            Native.resize(getWidth(), getHeight());
            mine = ++setUp;
            app = true;
        }
        // the native views' pictures come since the last frame, for this one to draw where it shows them
        NativeViews.latch();
        // the soft keyboard's height off the bottom (Host.imeBottom, as it moves): the app lays out above it, the
        // surface keeps its size (resizing it with each step of the keyboard's motion would be far too slow)
        float w = getWidth() / density, h = Math.max(1, getHeight() - Host.imeBottom) / density;
        if (Host.shotAt >= 0) {
            shotFrame(w, h);
            return;
        }
        // only a view's picture changed (pictureFrame): the last frame drawn again with it, the app not asked; a frame
        // the app or the system asked for is the app's
        long[] at = vsyncAt;
        if (pictured && !app) {
            Native.redraw();
            showAt(at[1]);
            NativeViews.framed(false);
            askedAtEnd = false;
            return;
        }
        long began = System.nanoTime();
        // (the frame before asked for this one: the one after it asked for now, before this one's work: askAhead)
        if (askedAtEnd) askAhead();
        // the vsync's time; a frame the system asked for (a resize) has none, and time never goes back
        long v = at[0];
        double now = v != 0 ? v / 1e6 : began / 1e6;
        if (now < lastFrame) now = lastFrame;
        lastFrame = now;
        // how late the frame before reached the screen (@hostapi.frame_late): the display's frames that passed past the one
        // after it without a frame, on the vsyncs' grid (its work over the display's frame and drawn on for the vsync it
        // asked ahead, shown at that vsync's refresh: none passed, it was in time; past that one too, this one's vsync is
        // the first after its work); 0 where it did not ask for this one (its vsync perhaps one during that work), or
        // either has no vsync. (Counted from when its work ended, a frame drawn on at once for the vsync asked ahead was
        // said late by a frame it was not: a page let go as the finger lifts, its slide held a frame and its first step
        // shown twice.)
        double late = 0;
        if (v != 0 && lastVsync != 0 && askedAtEnd) {
            long frames = Math.round((double) (v - lastVsync) / framePeriod);
            if (frames > 1) late = (frames - 1) * framePeriod / 1e6;
        }
        // drawn at the vsync after the frame before's: the hand moving what it holds, a frame each vsync
        boolean following = v > lastVsync && lastVsync != 0 && v - lastVsync < framePeriod * 3 / 2;
        lastVsync = v;
        // the system's back said before this frame's vsync (back(), below); what was said after it, the next frame's
        boolean later = takeBacks(v != 0 ? v : began);
        // (what it waits for said again by the frame, if it still does: Host.wakeAfter, from its time)
        wakeFor = -1;
        buildingFor = now;
        boolean more = Native.frame(w, h, density, now, late);
        buildingFor = -1;
        showAt(at[1]);
        askedAtEnd = more || later;
        drawn++;
        if (more || later || following) sayRate(true);
        else if (rateSaid) stillAfter(drawn);
        if (more || later) wantFrame();
        else ahead.set(false);
        // (the native views moved in it: their frames follow once they rest)
        NativeViews.framed(more || later);
        Script.frameDrawn();
        frameWorked(System.nanoTime() - began);
    }

    // ---- the drawing thread, as the system's own ----

    /**
     * This thread builds, lays out and draws every frame: what Compose's UI thread and HWUI's RenderThread do between
     * them. GLSurfaceView makes it a plain thread (nice 0), while the system raises the app in front's UI thread and
     * RenderThread (THREAD_PRIORITY_TOP_APP_BOOST, or SCHED_FIFO) and its scheduler and governor favour them: a frame
     * here could wait behind the core's thread, pictures decoding and the system's own work, on whatever core and clock
     * the phone gave it. Raised as a display thread, and its work per frame told to the system (ADPF's
     * PerformanceHintManager, as HWUI tells its frames' since Android 12) against the display's frame, so the CPUs it
     * runs on are clocked for it.
     */
    private void drawingThread() {
        try {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY);
        } catch (RuntimeException e) {
            Host.log("drawing thread: priority: " + e);
        }
        // (a session per thread: GLSurfaceView starts another as the view is shown again)
        int tid = android.os.Process.myTid();
        if (android.os.Build.VERSION.SDK_INT < 31 || tid == hintTid) return;
        if (hints != null) hints.close();
        hints = null;
        hintTid = tid;
        android.os.PerformanceHintManager pm = getContext().getSystemService(android.os.PerformanceHintManager.class);
        long target = framePeriod * 7 / 10;
        try {
            hints = pm == null ? null : pm.createHintSession(new int[] {tid}, target);
        } catch (RuntimeException e) {
            Host.log("drawing thread: hints: " + e);
        }
        hintTarget = target;
    }

    /** The system told what this thread's work over a frame (null: Android before 12, or a phone without ADPF). */
    private android.os.PerformanceHintManager.Session hints;
    private int hintTid;
    private long hintTarget;
    /**
     * The display's frame (ns), read as the view is shown and as the display changes its rate, and since Android 13 from
     * each vsync's timelines (main thread).
     */
    private volatile long framePeriod = 16_666_667L;

    /** The display's frame, ms. */
    double framePeriodMs() {
        return framePeriod / 1e6;
    }

    private final android.hardware.display.DisplayManager.DisplayListener displays =
            new android.hardware.display.DisplayManager.DisplayListener() {
                @Override public void onDisplayAdded(int id) {}

                @Override public void onDisplayRemoved(int id) {}

                @Override public void onDisplayChanged(int id) {
                    readFramePeriod();
                }
            };

    private void readFramePeriod() {
        android.view.Display d = getDisplay();
        if (d != null && d.getRefreshRate() > 1) framePeriod = (long) (1e9 / d.getRefreshRate());
        if (d == null) return;
        // the highest rate the display shows at the size it has now (another size is another mode, not a rate)
        android.view.Display.Mode m = d.getMode();
        float top = 0;
        for (android.view.Display.Mode o : d.getSupportedModes()) {
            if (o.getPhysicalWidth() == m.getPhysicalWidth() && o.getPhysicalHeight() == m.getPhysicalHeight())
                top = Math.max(top, o.getRefreshRate());
        }
        topRate = top;
    }

    // ---- the display's rate ----

    /**
     * The rate this surface's frames want of the display (Surface.setFrameRate), said as the system's own views say
     * theirs (a list flung, a view moved: Android 15's frame rate categories): the display's highest while the app
     * draws frame after frame (a motion, the hand moving what it holds), and from a finger going down (as the system's
     * touch boost: the motion it starts is not where the display goes over to it) until it lifts; nothing once a vsync
     * passes with none drawn and no finger on the screen. Withdrawn as a single vsync passed with none drawn while a
     * finger was down, it went down and up again within a gesture, wherever a vsync brought no touch (a finger slowing,
     * the touches' own rate a little off the display's), and each change of the display's rate can step what moves (OPPO
     * Find N6, 0.1.5814: scrolling stepped all along, its frames 1.3–2.7 ms).
     * A surface that says nothing is left at the rate the system picks for it from how often its buffers came: a phone
     * that does 120 Hz (an OPPO Find N6) kept the display at 60 for the app, every motion with half the frames its
     * own views' get. Said only while it moves: a rate said keeps the display at it for as long as the surface shows,
     * still or not.
     */
    private volatile float topRate;
    /** Whether this surface says the display's highest rate now (GL thread; a new surface says nothing). */
    private boolean rateSaid;
    /** The app's frames drawn (GL thread): one drawn since a frame that asked for none is told by it. */
    private int drawn;

    /** The surface says the display's highest rate, or nothing (GL thread). */
    private void sayRate(boolean on) {
        if (on == rateSaid || android.os.Build.VERSION.SDK_INT < 30) return;
        float rate = on ? topRate : 0;
        if (on && rate <= 0) return;
        android.view.Surface s = getHolder().getSurface();
        if (s == null || !s.isValid()) return;
        try {
            s.setFrameRate(rate, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
            rateSaid = on;
        } catch (RuntimeException e) {
            Host.log("display rate: " + e);
        }
    }

    /**
     * Frame {@code at} asked for none after it (GL thread): at the next vsync, after the touches it brings (a frame they
     * ask for is drawn at it), the app still with nothing drawn since, none asked and no finger down says no rate (the
     * frame after the finger lifts says, as it asks for none).
     */
    private void stillAfter(int at) {
        Host.main.post(() -> Choreographer.getInstance().postFrameCallback(t -> queueEvent(() -> {
            if (drawn == at && !appWanted.get() && !touching) sayRate(false);
        })));
    }

    /** Whether a finger is on the screen (main thread writes it, from its touches). */
    private volatile boolean touching;

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        readFramePeriod();
        android.hardware.display.DisplayManager dm = getContext().getSystemService(android.hardware.display.DisplayManager.class);
        if (dm != null) dm.registerDisplayListener(displays, Host.main);
    }

    @Override
    protected void onDetachedFromWindow() {
        android.hardware.display.DisplayManager dm = getContext().getSystemService(android.hardware.display.DisplayManager.class);
        if (dm != null) dm.unregisterDisplayListener(displays);
        super.onDetachedFromWindow();
    }

    /**
     * A frame's work done (GL thread): how long it took, against 70% of the display's frame as it is now. The system
     * clocks the CPUs so that a frame takes about as long as its target, one a little over as often as one a little
     * under; one over the display's frame misses the next vsync, so the target leaves room under it, as HWUI's does
     * (its frames' targets are 70% of their time).
     */
    private void frameWorked(long nanos) {
        if (hints == null) return;
        long target = framePeriod * 7 / 10;
        if (target != hintTarget) {
            hintTarget = target;
            hints.updateTargetWorkDuration(target);
        }
        if (nanos > 0) hints.reportActualWorkDuration(nanos);
    }

    // ---- the system's back ----

    /** What the system's back said (main thread), each with when (System.nanoTime) and its kind, x, progress, edge. */
    private final ArrayDeque<double[]> backs = new ArrayDeque<>();

    /**
     * The system's back (MainActivity's OnBackAnimationCallback, main thread), x in dp: drawn by the first frame whose
     * vsync is later than when it was said. Its gesture's steps come from the system's spring (BackProgressAnimator)
     * in a vsync's animation phase, as that vsync's frame (asked for in the same phase: vsync, below) may already be
     * drawing on the GL thread. Handed to the GL thread at once, a step went into that frame or the next as the two
     * threads raced: a frame got none, the next two, and the page following the finger stood still for a frame and
     * jumped two. A finger's touches come in the vsync's input phase, before its frame is asked for, and do not race.
     */
    void back(int kind, float x, float progress, int edge) {
        synchronized (backs) {
            backs.add(new double[] {System.nanoTime(), kind, x, progress, edge});
        }
        wantFrame();
    }

    /** Hands MoonBit the backs said before {@code before} (ns), in order (GL thread); whether any is left for later. */
    private boolean takeBacks(long before) {
        while (true) {
            double[] b;
            synchronized (backs) {
                b = backs.peek();
                if (b == null) return false;
                if (b[0] >= before) return true;
                backs.poll();
            }
            Native.back((int) b[1], (float) b[2], (float) b[3], (int) b[4]);
        }
    }

    // ---- vsync ----

    /**
     * The vsync the next frame is drawn for and when the system is to show it (ns, System.nanoTime's clock; 0: not said):
     * since Android 13, the expected presentation of the vsync's preferred frame timeline (Choreographer.FrameData), the
     * refresh a frame of the system's own drawn for that vsync is shown at.
     */
    private volatile long[] vsyncAt = {0, 0};
    private final AtomicBoolean wanted = new AtomicBoolean();
    private final Choreographer.FrameCallback vsync = t -> vsyncCame(t, 0);
    /** The vsync told with its frame's timelines (Timelines: Android 13's), made as first asked for. */
    private Object vsyncTimed;
    private final Runnable postVsync = () -> {
        if (android.os.Build.VERSION.SDK_INT >= 33) Timelines.post(this);
        else Choreographer.getInstance().postFrameCallback(vsync);
    };

    /** Android 13's vsync with its frame's timelines: a class of its own, loaded only there (older have no VsyncCallback). */
    private static final class Timelines {
        static void post(MBView v) {
            if (v.vsyncTimed == null) {
                v.vsyncTimed = (Choreographer.VsyncCallback) d -> {
                    long shows = d.getPreferredFrameTimeline().getExpectedPresentationTimeNanos();
                    // the display's frame now, as far apart as its timelines are: the rate the app's frames are shown
                    // at (since Android 16 the display's listener is told no change of rate unless it asks, so the
                    // frame read as the view was shown, at 60 Hz, stayed while the display went to 120 as the app
                    // moved); taken as the rate changes, not as the compositor's guess of it moves by a little
                    Choreographer.FrameTimeline[] tl = d.getFrameTimelines();
                    long period = tl.length > 1
                            ? tl[1].getExpectedPresentationTimeNanos() - tl[0].getExpectedPresentationTimeNanos() : 0;
                    if (period > 0 && Math.abs(period - v.framePeriod) * 16 > v.framePeriod) v.framePeriod = period;
                    v.vsyncCame(d.getFrameTimeNanos(), shows);
                };
            }
            Choreographer.getInstance().postVsyncCallback((Choreographer.VsyncCallback) v.vsyncTimed);
        }
    }

    /**
     * A vsync asked for came (main thread), at {@code t}, its frame shown at {@code shows} (vsyncAt): drawn for, where a
     * frame is wanted; where only the frame drawing now asked for it ahead (askAhead), kept for that frame to take as it
     * ends (ask), should it want one.
     */
    private void vsyncCame(long t, long shows) {
        vsyncAt = new long[] {t, shows};
        if (appWanted.get() || picturesOnly.get()) {
            wanted.set(false);
            requestRender();
            return;
        }
        ahead.set(true);
        wanted.set(false);
        // (a frame wanted as this was kept: the one asking saw it not yet kept, and asked for another vsync, or none)
        if ((appWanted.get() || picturesOnly.get()) && ahead.getAndSet(false)) requestRender();
    }

    /**
     * The vsync after the frame beginning now asked for before its work (GL thread), where the frame before asked for
     * this one (a motion going on): a frame asked for only as it ended had the first vsync after its work, so one whose
     * work went past the display's frame left a refresh with no new frame, what moved standing still for one and then
     * stepping two (an OPPO Find N6's inner screen, its frames 6–16 ms at 120 Hz). Asked ahead, the vsync comes while
     * the frame is drawn; one that ends after it draws the next at once, for that vsync and shown at its refresh
     * (showAt), as the system's own frames are asked for in the vsync before theirs: a frame over the display's frame
     * costs nothing where the next is lighter.
     */
    private void askAhead() {
        ahead.set(false);
        if (wanted.compareAndSet(false, true)) Host.main.post(postVsync);
    }

    /**
     * A vsync asked for ahead came and no frame was drawn for it (vsyncCame): the next frame wanted is drawn at once,
     * for it, while it is the latest vsync (a frame later than that is the next vsync's).
     */
    private final AtomicBoolean ahead = new AtomicBoolean();

    /** A frame wanted (appWanted or picturesOnly just set, from any thread): drawn for the vsync kept, or the next. */
    private void ask() {
        if (ahead.getAndSet(false) && System.nanoTime() - vsyncAt[0] < framePeriod) {
            requestRender();
            return;
        }
        if (!wanted.compareAndSet(false, true)) return;
        if (Looper.myLooper() == Looper.getMainLooper()) postVsync.run();
        else Host.main.post(postVsync);
    }

    /**
     * The frame being drawn (GL thread, before GLSurfaceView swaps it) shown at the refresh its vsync's timeline says
     * ({@code shows}, vsyncAt's), not sooner; at once where none is said (0: before Android 13, the keyboard's frames).
     * A frame of the system's own carries its vsync's timeline, and the compositor holds it until that refresh however
     * soon it is ready. One drawn here carried nothing and was shown at the first refresh after it was ready: at 120 Hz,
     * a frame drawn in a little less than a refresh was shown a refresh sooner after its vsync than one drawn in a little
     * more, so what moved went by uneven steps and the words shook. Held so, every frame is shown as long after its
     * vsync as the others. (Said half a refresh before it, as the compositor takes a frame at the first refresh after
     * the time it is given and its moments and the timeline's may be apart by a little; said on every frame, as the
     * surface keeps the last time given.)
     */
    private void showAt(long shows) {
        if (android.os.Build.VERSION.SDK_INT < 33) return;
        long at = shows != 0 ? shows - framePeriod / 2 : System.nanoTime();
        android.opengl.EGLExt.eglPresentationTimeANDROID(android.opengl.EGL14.eglGetCurrentDisplay(),
                android.opengl.EGL14.eglGetCurrentSurface(android.opengl.EGL14.EGL_DRAW), at);
    }

    /**
     * A frame now, at the vsync being drawn (main thread, within a Choreographer frame: the keyboard's motion said by
     * WindowInsetsAnimation's onProgress), not the next: what rides on the keyboard drawn in the frame the system
     * moves the keyboard in, not a vsync behind it.
     */
    void frameNow() {
        if (shotTaken) return;
        // (the frame's own vsync time is not public: now, a moment after it, never before a frame drawn; shown as soon as
        // it is drawn, as the keyboard moves)
        vsyncAt = new long[] {System.nanoTime(), 0};
        wanted.set(false);
        requestRender();
    }

    /**
     * The frame the app waits for (Host.wakeAfter: a resident cycle's next step), by its time (ms, System.nanoTime's
     * clock as the vsyncs'), or -1; and the time of the frame being built (GL thread), what a wait counts from.
     */
    volatile double wakeFor = -1;
    volatile double buildingFor = -1;

    /**
     * The frame for time `at` drawn (main thread, a little before it): asked for at the vsync before the first at or past
     * it, so drawn for that one, the vsyncs before it drawing nothing (not the vsync after a timer happens to fire: a step a frame or two late by as much as that
     * falls, a resident cycle's steps unevenly apart).
     */
    void wakeAt(double at) {
        if (wakeFor != at) return;
        Choreographer.getInstance().postFrameCallback(new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long t) {
                if (wakeFor != at) return;
                // (the vsync after this one is the frame's: asked for as any other, with its timelines)
                if ((t + framePeriod) / 1e6 < at - 0.5) {
                    Choreographer.getInstance().postFrameCallback(this);
                    return;
                }
                wakeFor = -1;
                wantFrame();
            }
        });
    }

    /** A frame at the next vsync (from any thread). */
    void wantFrame() {
        if (shotTaken) return;
        appWanted.set(true);
        ask();
    }

    /**
     * A native view's new picture to show (NativeViews.Picture, from any thread): the last frame drawn again at the next
     * vsync, with it, unless the app has asked for a frame by then.
     */
    void pictureFrame() {
        if (shotTaken) return;
        picturesOnly.set(true);
        ask();
    }

    /** A frame asked of the app (wantFrame), or only for a view's picture (pictureFrame), since the last was drawn. */
    private final AtomicBoolean appWanted = new AtomicBoolean(), picturesOnly = new AtomicBoolean();

    /** Runs r on the GL thread and asks for a frame. */
    void toGL(Runnable r) {
        queueEvent(r);
        wantFrame();
    }

    // ---- input ----

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        // each finger by its pointer id (an index is only its place in this event): handed on as it comes, down, moved,
        // up or called off (pointer kinds 10-13, the id where a button goes), what they come to the app's to work out
        // (touches.mbt: two of them its, the first let go the second the first, one called off all of it)
        final int a = e.getActionMasked();
        final double t = e.getEventTime();
        switch (a) {
            case MotionEvent.ACTION_DOWN:
                // (the display's highest from a finger going down: what it moves moves at it from its first frame)
                touching = true;
                queueEvent(() -> sayRate(true));
                requestFocus();
                break;
            case MotionEvent.ACTION_UP: Host.lifts++; touching = false; break;
            case MotionEvent.ACTION_CANCEL: touching = false; break;
            default: break;
        }
        switch (a) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN:
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP: {
                final int i = e.getActionIndex();
                final int id = e.getPointerId(i);
                final float x = e.getX(i) / density, y = e.getY(i) / density;
                final int phase = a == MotionEvent.ACTION_DOWN || a == MotionEvent.ACTION_POINTER_DOWN ? 10 : 12;
                toGL(() -> Native.touch(phase, id, x, y, t));
                return true;
            }
            case MotionEvent.ACTION_CANCEL: {
                // (called off: each finger it had, all of it)
                final int n = e.getPointerCount();
                final int[] ids = new int[n];
                final float[] xs = new float[n], ys = new float[n];
                for (int p = 0; p < n; p++) {
                    ids[p] = e.getPointerId(p);
                    xs[p] = e.getX(p) / density;
                    ys[p] = e.getY(p) / density;
                }
                toGL(() -> { for (int p = 0; p < n; p++) Native.touch(13, ids[p], xs[p], ys[p], t); });
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                // each finger's samples batched into the move (MotionEvent's history) and the event itself, each at its
                // own time (uptime ms, as Compose's PointerInputChange has them)
                final int n = e.getPointerCount(), h = e.getHistorySize();
                final int[] ids = new int[n];
                final float[] xs = new float[n * (h + 1)], ys = new float[n * (h + 1)];
                final double[] ts = new double[h + 1];
                for (int k = 0; k < h; k++) ts[k] = e.getHistoricalEventTime(k);
                ts[h] = t;
                for (int p = 0; p < n; p++) {
                    ids[p] = e.getPointerId(p);
                    for (int k = 0; k < h; k++) {
                        xs[p * (h + 1) + k] = e.getHistoricalX(p, k) / density;
                        ys[p * (h + 1) + k] = e.getHistoricalY(p, k) / density;
                    }
                    xs[p * (h + 1) + h] = e.getX(p) / density;
                    ys[p * (h + 1) + h] = e.getY(p) / density;
                }
                toGL(() -> {
                    for (int k = 0; k <= h; k++)
                        for (int p = 0; p < n; p++) Native.touch(11, ids[p], xs[p * (h + 1) + k], ys[p * (h + 1) + k], ts[k]);
                });
                return true;
            }
            default: return true;
        }
    }

    /** What the clipboard holds, as words, into the focused field (a paste: KEYCODE_PASTE, the keyboard's menu). */
    // ── the floating text menu (Host.textMenu): the system's text toolbar over a field's words ──

    private android.view.ActionMode textMenu;
    private final android.graphics.Rect textMenuRect = new android.graphics.Rect();
    private int textMenuCan;

    /** Shown over (x, y, w, h) in dp with what {@code can} offers, moved there when it is up; or put away. */
    void textMenu(boolean shown, double x, double y, double w, double h, int can) {
        if (!shown) {
            if (textMenu != null) textMenu.finish();
            textMenu = null;
            return;
        }
        textMenuRect.set((int) Math.floor(x * density), (int) Math.floor(y * density),
                (int) Math.ceil((x + w) * density), (int) Math.ceil((y + h) * density));
        textMenuCan = can;
        if (textMenu != null) {
            textMenu.invalidate();
            textMenu.invalidateContentRect();
            return;
        }
        textMenu = startActionMode(new android.view.ActionMode.Callback2() {
            private void items(android.view.Menu m) {
                m.clear();
                if ((textMenuCan & 1) != 0) m.add(0, android.R.id.cut, 0, android.R.string.cut);
                if ((textMenuCan & 2) != 0) m.add(0, android.R.id.copy, 1, android.R.string.copy);
                // nothing on the clipboard: no 粘贴 (as Compose's text toolbar offers it only then)
                if ((textMenuCan & 4) != 0 && clipHasText()) m.add(0, android.R.id.paste, 2, android.R.string.paste);
                if ((textMenuCan & 8) != 0) m.add(0, android.R.id.selectAll, 3, android.R.string.selectAll);
            }

            @Override public boolean onCreateActionMode(android.view.ActionMode mode, android.view.Menu m) { items(m); return true; }

            @Override public boolean onPrepareActionMode(android.view.ActionMode mode, android.view.Menu m) { items(m); return true; }

            @Override public boolean onActionItemClicked(android.view.ActionMode mode, android.view.MenuItem item) {
                int id = item.getItemId();
                // as the input method's own (MBInput.performContextMenuAction): the keys and the paste the field takes
                if (id == android.R.id.paste) paste();
                else if (id == android.R.id.selectAll) toGL(() -> Native.key(12, 0));
                else if (id == android.R.id.copy) toGL(() -> Native.key(13, 0));
                else if (id == android.R.id.cut) toGL(() -> Native.key(14, 0));
                mode.finish();
                return true;
            }

            @Override public void onDestroyActionMode(android.view.ActionMode mode) {
                if (textMenu == mode) textMenu = null;
            }

            @Override public void onGetContentRect(android.view.ActionMode mode, android.view.View v, android.graphics.Rect out) {
                out.set(textMenuRect);
            }
        }, android.view.ActionMode.TYPE_FLOATING);
    }

    /** Whether the clipboard holds something to paste (ClipboardManager.hasPrimaryClip). */
    private boolean clipHasText() {
        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        return cm != null && cm.hasPrimaryClip();
    }

    void paste() {
        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        android.content.ClipData clip = cm.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence t = clip.getItemAt(0).coerceToText(getContext());
        if (t == null || t.length() == 0) return;
        String s = t.toString();
        // (text kind 8: put in as typed, a step of its own to undo)
        toGL(() -> Native.text(8, s, 0, 0));
    }

    /** A key with the focus a key catcher's (Device.catching): its named keys and shortcuts as keys, a character as
     * text; false for what is not the catcher's (Back). */
    boolean catchKey(KeyEvent e) {
        if (e.getKeyCode() == KeyEvent.KEYCODE_BACK) return false;
        int[] k = Device.catchKey(e);
        if (k != null) {
            toGL(() -> Native.key(k[0], k[1]));
            return true;
        }
        int ch = e.getUnicodeChar();
        if (ch <= 0) return false;
        String s = new String(Character.toChars(ch));
        toGL(() -> Native.text(0, s, 0, 0));
        return true;
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        if (Device.catching && Host.imeActive && catchKey(e)) return true;
        if (code == KeyEvent.KEYCODE_PASTE || (code == KeyEvent.KEYCODE_V && e.isCtrlPressed())) {
            if (Host.imeActive) paste();
            return true;
        }
        int sk = shortcutKey(e);
        if (sk != 0) {
            int mods = Device.keyMods(e);
            toGL(() -> Native.key(sk, mods));
            return true;
        }
        int k = keyCode(code);
        if (k != 0) {
            int mods = Device.keyMods(e);
            toGL(() -> Native.key(k, mods));
            return true;
        }
        int ch = e.getUnicodeChar();
        if (ch != 0 && Host.imeActive) {
            String s = new String(Character.toChars(ch));
            toGL(() -> Native.text(0, s, 0, 0));
            return true;
        }
        return super.onKeyDown(code, e);
    }

    /** A letter or digit with Ctrl or Meta held (a hardware keyboard's shortcut, which types no character): Ctrl+A, C
     * and X the field's select all, copy and cut (12, 13, 14, as Windows' host sends them), any other the app's or the
     * field's key as 1000 + the character (Ctrl+Z, Ctrl+Y to undo and do again, Ctrl+K); 0 for none. */
    static int shortcutKey(KeyEvent e) {
        if (!e.isCtrlPressed() && !e.isMetaPressed()) return 0;
        int k = e.getKeyCode();
        int ch;
        if (k >= KeyEvent.KEYCODE_A && k <= KeyEvent.KEYCODE_Z) ch = 'a' + (k - KeyEvent.KEYCODE_A);
        else if (k >= KeyEvent.KEYCODE_0 && k <= KeyEvent.KEYCODE_9) ch = '0' + (k - KeyEvent.KEYCODE_0);
        else return 0;
        if (e.isCtrlPressed()) {
            if (ch == 'a') return 12;
            if (ch == 'c') return 13;
            if (ch == 'x') return 14;
        }
        return 1000 + ch;
    }

    static int keyCode(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_DEL: return 1;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 2;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 3;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 4;
            case KeyEvent.KEYCODE_DPAD_UP: return 5;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 6;
            case KeyEvent.KEYCODE_ENTER: return 7;
            case KeyEvent.KEYCODE_MOVE_HOME: return 8;
            case KeyEvent.KEYCODE_MOVE_END: return 9;
            default: return 0;
        }
    }

    @Override
    public boolean onCheckIsTextEditor() {
        return Host.imeActive;
    }

    /** The field's input connection, the last made (null while a key catcher has the focus). */
    MBInput input;

    @Override
    public InputConnection onCreateInputConnection(EditorInfo out) {
        if (Device.catching) {
            // a key catcher's (Device): no text of its own, no suggestions, the keyboard's Enter a key (as still.fail's
            // KeyCatcher)
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
            out.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_ACTION_NONE;
            out.initialSelStart = 0;
            out.initialSelEnd = 0;
            input = null;
            return new CatchInput(this);
        }
        // multi-line, with no action of the keyboard's own: its Enter is a key the field decides on (a new line in
        // still.fail's composer, as its Android app's field does; the demo sends)
        out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
        out.imeOptions = EditorInfo.IME_ACTION_NONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION
                | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        if (Device.imeAction == 1) {
            // a search field's (hostapi ime_action): one line, its Enter the keyboard's search key, which comes as Enter
            // (performEditorAction)
            out.inputType = InputType.TYPE_CLASS_TEXT;
            out.imeOptions = EditorInfo.IME_ACTION_SEARCH | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 2) {
            // an address's: the keyboard's for addresses, its Enter a go key (Compose's ImeAction.Go, KeyboardType.Uri)
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI;
            out.imeOptions = EditorInfo.IME_ACTION_GO | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 3) {
            // a number's: digits, its Enter a done key (Compose's ImeAction.Done, KeyboardType.Number)
            out.inputType = InputType.TYPE_CLASS_NUMBER;
            out.imeOptions = EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        }
        out.initialSelStart = Host.selStart;
        out.initialSelEnd = Host.selEnd;
        input = new MBInput(this);
        return input;
    }

    /**
     * What an input method talks to while a key catcher has the focus (Device): no text of its own; what it commits,
     * composes and deletes goes to MoonBit as events (src/ui/device.mbt takes them).
     */
    static class CatchInput extends BaseInputConnection {
        final MBView view;
        volatile boolean composing;
        /** What is being composed (shown at the caret, not yet in MoonBit's text). */
        volatile String composingText = "";

        CatchInput(MBView v) {
            super(v, false);
            view = v;
        }

        @Override
        public boolean commitText(CharSequence text, int pos) {
            String s = text.toString();
            if (Host.imeLog()) Host.log("ime: commitText " + s);
            composing = false;
            composingText = "";
            if (s.equals("\n")) {
                view.toGL(() -> Native.key(7, 0));
            } else {
                view.toGL(() -> Native.text(0, s, 0, 0));
            }
            return true;
        }

        @Override
        public boolean setComposingText(CharSequence text, int pos) {
            String s = text.toString();
            if (Host.imeLog()) Host.log("ime: setComposingText " + s);
            composingText = s;
            composing = s.length() > 0;
            view.toGL(() -> Native.text(1, s, s.length(), 0));
            return true;
        }

        @Override
        public boolean finishComposingText() {
            if (Host.imeLog()) Host.log("ime: finishComposingText (composing " + composing + ")");
            if (composing) {
                composing = false;
                composingText = "";
                view.toGL(() -> Native.text(2, "", 0, 0));
            }
            return true;
        }

        @Override
        public boolean setSelection(int start, int end) {
            view.toGL(() -> Native.text(3, "", start, end));
            return true;
        }

        @Override
        public boolean deleteSurroundingText(int before, int after) {
            // (a field takes it as its Backspace, its Delete; a key catcher as that many: src/ui/device.mbt)
            if (before > 0 || after > 0) view.toGL(() -> Native.text(4, "", before, after));
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent e) {
            if (e.getAction() != KeyEvent.ACTION_DOWN) return true;
            if (Device.catching) {
                view.catchKey(e);
                return true;
            }
            if (e.getKeyCode() == KeyEvent.KEYCODE_PASTE) { view.paste(); return true; }
            int k = keyCode(e.getKeyCode());
            if (k == 0) k = shortcutKey(e);
            if (k != 0) {
                int kk = k, mods = Device.keyMods(e);
                view.toGL(() -> Native.key(kk, mods));
                return true;
            }
            int ch = e.getUnicodeChar();
            if (ch != 0) {
                String s = new String(Character.toChars(ch));
                view.toGL(() -> Native.text(0, s, 0, 0));
            }
            return true;
        }

        @Override
        public boolean performContextMenuAction(int id) {
            // a key catcher has no text to select, copy or paste into
            if (Device.catching) return false;
            if (id == android.R.id.paste || id == android.R.id.pasteAsPlainText) view.paste();
            else if (id == android.R.id.selectAll) view.toGL(() -> Native.key(12, 0));
            else if (id == android.R.id.copy) view.toGL(() -> Native.key(13, 0));
            else if (id == android.R.id.cut) view.toGL(() -> Native.key(14, 0));
            return true;
        }

        @Override
        public boolean performEditorAction(int action) {
            view.toGL(() -> Native.key(7, 0));
            return true;
        }

        @Override
        public CharSequence getTextBeforeCursor(int n, int flags) {
            String t = Host.imeText;
            int a = Math.max(0, Math.min(Host.selStart, t.length()));
            return t.substring(Math.max(0, a - n), a);
        }

        @Override
        public CharSequence getTextAfterCursor(int n, int flags) {
            String t = Host.imeText;
            int b = Math.max(0, Math.min(Host.selEnd, t.length()));
            return t.substring(b, Math.min(t.length(), b + n));
        }

        @Override
        public CharSequence getSelectedText(int flags) {
            String t = Host.imeText;
            int a = Math.max(0, Math.min(Host.selStart, t.length()));
            int b = Math.max(a, Math.min(Host.selEnd, t.length()));
            return a == b ? null : t.substring(a, b);
        }
    }

    /**
     * What an input method talks to while a field has the focus: the field's words kept here as well, in an Editable
     * the input method's edits are made on at once, as a TextView's are. An input method reads what it just did right
     * after doing it (the word before the caret, to put a space after a full stop or between Chinese and English;
     * where the caret is, which it is told after each edit): answered from words MoonBit had not taken in yet, it
     * read the field as before its edit, took the caret as moved by someone else and forgot the space it owed. Each
     * edit (a batch of them: once the batch ends) goes to MoonBit as the field's whole state (src/ui/editor.mbt
     * text_set), and the input method is told the selection then, as a TextView tells it; what MoonBit changes itself
     * (a key, the app clearing the field once sent) comes back after its frame (Host.setIme) and is put in here.
     */
    static final class MBInput extends BaseInputConnection {
        final MBView view;
        final Editable ed;
        private int batch;
        /** What MoonBit was last told, or last told this: the state it has (once it has taken what it was sent). */
        String saidText;
        int saidA, saidB, saidCs = -1, saidCe = -1;

        MBInput(MBView v) {
            super(v, true);
            view = v;
            String t = Host.imeText;
            ed = Editable.Factory.getInstance().newEditable(t);
            int a = Math.max(0, Math.min(Host.selStart, t.length())), b = Math.max(0, Math.min(Host.selEnd, t.length()));
            Selection.setSelection(ed, a, b);
            saidText = t;
            saidA = a;
            saidB = b;
        }

        @Override
        public Editable getEditable() {
            return ed;
        }

        @Override
        public boolean beginBatchEdit() {
            batch++;
            return true;
        }

        @Override
        public boolean endBatchEdit() {
            if (batch > 0) batch--;
            if (batch == 0) edited();
            return batch > 0;
        }

        /** The field's state after the input method's edits, to MoonBit and to the input method, when it changed. */
        void edited() {
            if (batch > 0) return;
            String t = ed.toString();
            int a = Selection.getSelectionStart(ed), b = Selection.getSelectionEnd(ed);
            int cs = getComposingSpanStart(ed), ce = getComposingSpanEnd(ed);
            if (cs > ce) { int x = cs; cs = ce; ce = x; }
            if (t.equals(saidText) && a == saidA && b == saidB && cs == saidCs && ce == saidCe) return;
            saidText = t;
            saidA = a;
            saidB = b;
            saidCs = cs;
            saidCe = ce;
            final int seq = ++Host.imeSent;
            final int fa = a, fb = b, fcs = cs, fce = ce;
            if (Host.imeLog()) Host.log("ime: edited " + a + "," + b + " composing " + cs + "," + ce + " (" + t.length() + ")");
            view.toGL(() -> {
                Native.text(6, "", fcs, fce);
                Native.text(5, t, fa, fb);
                Host.imeTaken = seq;
            });
            imm().updateSelection(view, a, b, cs, ce);
        }

        InputMethodManager imm() {
            return (InputMethodManager) view.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        }

        /**
         * MoonBit's own change to the field (Host.setIme, on the main thread): its words `text` (without what is
         * composed) and selection, once it has taken every edit sent it. Put in here when they are not what it was
         * told; true then (the input method to be told).
         */
        boolean took(String text, int a, int b) {
            int cs = saidCs, ce = saidCe;
            // what it was told, as MoonBit keeps it: a composition holding the caret apart from its words (editor.mbt)
            String has = saidText;
            int ha = saidA, hb = saidB;
            boolean comp = cs >= 0 && ce > cs && ha == hb && ha >= cs && ha <= ce;
            if (comp) {
                has = saidText.substring(0, cs) + saidText.substring(ce);
                ha = cs;
                hb = cs;
            }
            if (text.equals(has) && Math.min(a, b) == Math.min(ha, hb) && Math.max(a, b) == Math.max(ha, hb)) return false;
            removeComposingSpans(ed);
            ed.replace(0, ed.length(), text);
            int n = text.length();
            Selection.setSelection(ed, Math.max(0, Math.min(a, n)), Math.max(0, Math.min(b, n)));
            saidText = text;
            saidA = Selection.getSelectionStart(ed);
            saidB = Selection.getSelectionEnd(ed);
            saidCs = -1;
            saidCe = -1;
            return true;
        }

        @Override
        public boolean commitText(CharSequence text, int pos) {
            if (Host.imeLog()) Host.log("ime: commitText " + text);
            if (text.toString().equals("\n")) {
                // Enter: the field's to decide (a new line, or sent), after what is composed is in
                finishComposingText();
                view.toGL(() -> Native.key(7, 0));
                return true;
            }
            return super.commitText(text, pos);
        }

        @Override
        public boolean setComposingText(CharSequence text, int pos) {
            if (Host.imeLog()) Host.log("ime: setComposingText " + text);
            return super.setComposingText(text, pos);
        }

        @Override
        public boolean finishComposingText() {
            if (Host.imeLog()) Host.log("ime: finishComposingText");
            boolean r = super.finishComposingText();
            edited();
            return r;
        }

        @Override
        public boolean setComposingRegion(int start, int end) {
            boolean r = super.setComposingRegion(start, end);
            edited();
            return r;
        }

        @Override
        public boolean setSelection(int start, int end) {
            boolean r = super.setSelection(start, end);
            edited();
            return r;
        }

        @Override
        public boolean deleteSurroundingText(int before, int after) {
            boolean r = super.deleteSurroundingText(before, after);
            edited();
            return r;
        }

        @Override
        public boolean deleteSurroundingTextInCodePoints(int before, int after) {
            boolean r = super.deleteSurroundingTextInCodePoints(before, after);
            edited();
            return r;
        }

        /** Backspace (`back`) or Delete sent as a key by the input method: made here, as a TextView makes it. */
        void deleteKey(boolean back) {
            removeComposingSpans(ed);
            int a = Selection.getSelectionStart(ed), b = Selection.getSelectionEnd(ed);
            if (a > b) { int x = a; a = b; b = x; }
            if (a == b) {
                // a grapheme cluster (an emoji of several code points, a letter and its marks)
                BreakIterator g = BreakIterator.getCharacterInstance();
                g.setText(ed.toString());
                if (back) {
                    if (a == 0) { edited(); return; }
                    a = g.preceding(a);
                } else {
                    if (b >= ed.length()) { edited(); return; }
                    b = g.following(b);
                }
            }
            ed.delete(a, b);
            Selection.setSelection(ed, a);
            edited();
        }

        @Override
        public boolean sendKeyEvent(KeyEvent e) {
            if (e.getAction() != KeyEvent.ACTION_DOWN) return true;
            if (e.getKeyCode() == KeyEvent.KEYCODE_PASTE) { view.paste(); return true; }
            if ((e.getKeyCode() == KeyEvent.KEYCODE_DEL || e.getKeyCode() == KeyEvent.KEYCODE_FORWARD_DEL)
                    && !e.isShiftPressed() && !e.isCtrlPressed() && !e.isAltPressed()) {
                deleteKey(e.getKeyCode() == KeyEvent.KEYCODE_DEL);
                return true;
            }
            int k = keyCode(e.getKeyCode());
            if (k != 0) {
                int mods = Device.keyMods(e);
                view.toGL(() -> Native.key(k, mods));
                return true;
            }
            int ch = e.getUnicodeChar();
            if (ch != 0) super.commitText(new String(Character.toChars(ch)), 1);
            return true;
        }

        @Override
        public boolean performContextMenuAction(int id) {
            if (id == android.R.id.paste || id == android.R.id.pasteAsPlainText) view.paste();
            else if (id == android.R.id.selectAll) view.toGL(() -> Native.key(12, 0));
            else if (id == android.R.id.copy) view.toGL(() -> Native.key(13, 0));
            else if (id == android.R.id.cut) view.toGL(() -> Native.key(14, 0));
            return true;
        }

        @Override
        public boolean performEditorAction(int action) {
            view.toGL(() -> Native.key(7, 0));
            return true;
        }

        @Override
        public ExtractedText getExtractedText(ExtractedTextRequest req, int flags) {
            ExtractedText x = new ExtractedText();
            x.text = ed.toString();
            x.startOffset = 0;
            x.partialStartOffset = -1;
            x.partialEndOffset = -1;
            x.selectionStart = Selection.getSelectionStart(ed);
            x.selectionEnd = Selection.getSelectionEnd(ed);
            x.flags = 0;
            return x;
        }
    }
}
