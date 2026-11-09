package dev.mbui;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Which vsync the app's next frame is drawn for, and what rate the surface says of the display (MBView's, kept apart
 * from Android so a test can run it: FramePacerTest, on its own clock and threads). MBView hands it the system's
 * vsyncs, the frames' work and the hand; it asks MBView's Platform for a vsync, a frame drawn and a rate said. Its
 * threads are MBView's: the main thread's (vsyncs, the hand), the drawing thread's (frames, the rate), any (a frame
 * wanted).
 */
final class FramePacer {
    /** What the pacer asks of the system (MBView's; the test's own). */
    interface Platform {
        /** The system's clock (ns), the vsyncs'. */
        long nanoTime();

        /** Whether this is the main thread. */
        boolean onMain();

        /** {@code r} run on the main thread, after what is there now. */
        void postMain(Runnable r);

        /** The next vsync asked for (main thread): {@link #vsyncCame} told at it. */
        void postVsync();

        /** {@code r} run on the drawing thread once the next vsync has come (asked on the main thread). */
        void atNextVsyncOnDrawing(Runnable r);

        /** A frame drawn on the drawing thread, as soon as it can (GLSurfaceView's requestRender). */
        void requestRender();

        /** The surface says the display's rate {@code rate} (0: nothing); false where it cannot be said. */
        boolean setRate(float rate);

        /** Whether the app's field is being typed into (the focus, or the soft keyboard up over it). */
        boolean typing();
    }

    private final Platform p;

    FramePacer(Platform p) {
        this.p = p;
    }

    /**
     * The display's frame (ns), read as the view is shown and as the display changes its rate, and since Android 13 from
     * each vsync's timelines (main thread).
     */
    volatile long framePeriod = 16_666_667L;
    /** The display's highest rate at its size now (MBView's readFramePeriod). */
    volatile float topRate;
    /** Whether a finger is on the screen (main thread writes it, from its touches). */
    volatile boolean touching;

    /**
     * The vsync the next frame is drawn for and when the system is to show it (ns, the system's clock; 0: not said): since
     * Android 13, the expected presentation of the vsync's preferred frame timeline (Choreographer.FrameData), the
     * refresh a frame of the system's own drawn for that vsync is shown at.
     */
    private volatile long[] vsyncAt = {0, 0};
    private final AtomicBoolean wanted = new AtomicBoolean();
    /**
     * A vsync asked for ahead came and no frame was drawn for it (vsyncCame): the next frame wanted is drawn at once,
     * for it, while it is the latest vsync (a frame later than that is the next vsync's).
     */
    private final AtomicBoolean ahead = new AtomicBoolean();
    /** A frame asked of the app (wantFrame), or only for a view's picture (pictureFrame), since the last was drawn. */
    final AtomicBoolean appWanted = new AtomicBoolean(), picturesOnly = new AtomicBoolean();

    private double lastFrame;
    // the frame before's vsync (0: none, or it had none), and whether it asked for this one (askAhead: the vsync after
    // its own, or where its work went past that one, the first after its work)
    private long lastVsync;
    private boolean askedAtEnd;

    /** The vsync the frame beginning now is for (its time, when it is shown; 0: not said). */
    long[] vsyncAt() {
        return vsyncAt;
    }

    /**
     * A vsync asked for came (main thread), at {@code t}, its frame shown at {@code shows} (vsyncAt): drawn for, where a
     * frame is wanted; where only the frame drawing now asked for it ahead (askAhead), kept for that frame to take as it
     * ends (ask), should it want one.
     */
    void vsyncCame(long t, long shows) {
        vsyncAt = new long[] {t, shows};
        if (appWanted.get() || picturesOnly.get()) {
            wanted.set(false);
            p.requestRender();
            return;
        }
        ahead.set(true);
        wanted.set(false);
        // (a frame wanted as this was kept: the one asking saw it not yet kept, and asked for another vsync, or none)
        if ((appWanted.get() || picturesOnly.get()) && ahead.getAndSet(false)) p.requestRender();
    }

    /**
     * The vsync after the frame beginning now asked for before its work (drawing thread), where the frame before asked
     * for this one (a motion going on): a frame asked for only as it ended had the first vsync after its work, so one
     * whose work went past the display's frame left a refresh with no new frame, what moved standing still for one and
     * then stepping two (an OPPO Find N6's inner screen, its frames 6–16 ms at 120 Hz). Asked ahead, the vsync comes
     * while the frame is drawn; one that ends after it draws the next at once, for that vsync and shown at its refresh
     * (showAt), as the system's own frames are asked for in the vsync before theirs: a frame over the display's frame
     * costs nothing where the next is lighter.
     */
    private void askAhead() {
        ahead.set(false);
        if (wanted.compareAndSet(false, true)) p.postMain(p::postVsync);
    }

    /** A frame wanted (appWanted or picturesOnly just set, from any thread): drawn for the vsync kept, or the next. */
    private void ask() {
        if (ahead.getAndSet(false) && p.nanoTime() - vsyncAt[0] < framePeriod) {
            p.requestRender();
            return;
        }
        if (!wanted.compareAndSet(false, true)) return;
        if (p.onMain()) p.postVsync();
        else p.postMain(p::postVsync);
    }

    /** A frame at the next vsync (from any thread). */
    void wantFrame() {
        appWanted.set(true);
        ask();
    }

    /** Only a native view's picture to show again (from any thread): the last frame drawn again at the next vsync. */
    void pictureFrame() {
        picturesOnly.set(true);
        ask();
    }

    /**
     * A frame now, at the vsync being drawn (main thread, within a Choreographer frame: the keyboard's motion), not the
     * next. (The frame's own vsync time is not public: now, a moment after it, never before a frame drawn; shown as soon
     * as it is drawn.)
     */
    void frameNow() {
        vsyncAt = new long[] {p.nanoTime(), 0};
        wanted.set(false);
        p.requestRender();
    }

    /** The last frame drawn again for a view's picture alone (drawing thread): it asked for none after it. */
    void redrawn() {
        askedAtEnd = false;
    }

    /** A frame of the app's begun (drawing thread): the time it is built for, how late it is, whether it follows. */
    static final class Begun {
        /** its vsync (0: none) and when it is shown (0: not said) */
        final long vsync, shows;
        /** the time it is built for (ms) and how late the frame before reached the screen (ms: @hostapi.frame_late) */
        final double now, late;
        /** drawn at the vsync after the frame before's: the hand moving what it holds, a frame each vsync */
        final boolean following;

        Begun(long vsync, long shows, double now, double late, boolean following) {
            this.vsync = vsync;
            this.shows = shows;
            this.now = now;
            this.late = late;
            this.following = following;
        }
    }

    /** The app's frame beginning now (drawing thread), at {@code began} (the system's clock), for {@code at} (vsyncAt). */
    Begun begin(long[] at, long began) {
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
        return new Begun(v, at[1], now, late, following);
    }

    /**
     * The app's frame ended (drawing thread): whether it asks for another ({@code more}, what it said; {@code later}, a
     * back said for a later vsync), whether it followed the one before (Begun's), and the rate what moves on by the
     * clock alone needs where the frame said one ({@code paced}, MBView.framesPaced: its next woken for, not asked for
     * here; 0 none): the rate said, the next asked for. Paced, what moves is said at its rate, the display free to
     * refresh as slowly; anything else moving, at the display's highest.
     */
    void ended(boolean more, boolean later, boolean following, float paced) {
        askedAtEnd = more || later;
        drawn++;
        if (paced > 0 && !more && !later && !touching && !p.typing()) {
            moved = drawn;
            sayRate(paced);
        } else if (more || later || following) {
            moved = drawn;
            sayRate(true);
        } else if (p.typing()) {
            // (typing: what it draws comes as keys are struck, its fingers on the keyboard's window, not on this surface
            // and nothing of the app's own moving; each key's frame at the display's highest, 2026-11-05)
            sayRate(true);
        } else if (rateSaid != 0) stillAfter(moved);
        if (more || later) wantFrame();
        else ahead.set(false);
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
    /** The rate this surface says of the display now (drawing thread; 0 none: a new surface says nothing). */
    private float rateSaid;
    /** The app's frames drawn (drawing thread): one drawn since a frame that asked for none is told by it. */
    private int drawn;
    /** The last frame drawn that moved something (drawing thread): a motion, the hand moving what it holds. */
    private int moved;
    /** The motion whose end is being counted down to saying no rate (drawing thread; -1 none). */
    private int stillFrom = -1;

    /** The rate the surface says of the display now (drawing thread; 0 none). */
    float rateSaid() {
        return rateSaid;
    }

    /** The surface says the display's highest rate, or nothing (drawing thread). */
    void sayRate(boolean on) {
        if (on && topRate <= 0) return;
        sayRate(on ? topRate : 0);
    }

    /** The surface says the display's rate {@code rate} (drawing thread; 0 nothing). */
    private void sayRate(float rate) {
        if (rate == rateSaid) return;
        if (p.setRate(rate)) rateSaid = rate;
    }

    /**
     * The motion that ended with frame {@code at} (drawing thread): no rate said once the display's highest rate's worth of
     * vsyncs (a second) passed with nothing moved since, none asked and no finger down. A frame drawn meanwhile that moves
     * nothing (a spinner's step, a page's words coming in) does not keep it. Said at once after the motion, the display
     * went down to the rate the system picks from how often frames came (a spinner stepping: 12-60 Hz on an OPPO Find
     * N6), and the next flick's first frames stepped up through it at 83, 17, 17, 17 ms before 8.3 (2026-11-04: 5-8
     * frames at the start of every swipe, the app's own work 2-5 ms each): a list is flicked again well within a second.
     */
    private void stillAfter(int at) {
        if (stillFrom == at) return;
        stillFrom = at;
        stillFor(at, Math.max(1, Math.round(topRate)));
    }

    private void stillFor(int at, int left) {
        p.atNextVsyncOnDrawing(() -> {
            if (moved != at || appWanted.get() || touching || p.typing() || rateSaid == 0) {
                if (stillFrom == at) stillFrom = -1;
                return;
            }
            if (left > 1) {
                stillFor(at, left - 1);
                return;
            }
            stillFrom = -1;
            sayRate(false);
        });
    }

    /** The field's typing begun or ended (drawing thread): the rate said or let go from now. */
    void typingChanged() {
        if (p.typing()) sayRate(true);
        else if (rateSaid != 0) stillAfter(moved);
    }
}
