package dev.mbui;

import android.content.Context;
import android.opengl.GLSurfaceView;
import android.os.Looper;
import android.text.InputType;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ViewTreeObserver;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.util.concurrent.atomic.AtomicBoolean;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * The surface the MoonBit app draws on. Everything MoonBit runs on the GL
 * thread: frames there, and input is queued onto it. Frames are paced by the
 * display's vsync (Choreographer), one per vsync at most, each told that
 * vsync's time, as Compose's frames are: a frame asked for while touches are
 * handled (the input phase of a vsync) is drawn at that vsync, one asked for
 * by a frame (an animation) at the next.
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
        // On top of the window, translucent: native views (NativeViews: a player, a page) sit under it and show
        // through the holes the app paints (transparent, kind 9); everywhere else each frame is opaque.
        getHolder().setFormat(android.graphics.PixelFormat.TRANSLUCENT);
        setZOrderOnTop(true);
        setPreserveEGLContextOnPause(true);
        setRenderer(this);
        setRenderMode(RENDERMODE_WHEN_DIRTY);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    // ---- GL thread ----

    @Override
    public void onSurfaceCreated(GL10 gl, EGLConfig config) {
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
        Native.resize(w, h);
    }

    private double lastFrame;

    // A picture at a declared moment (Host.shotAt, --ei shot_at MS: scripts/shots.sh android): the run's frames are on
    // a clock of their own, 1/60 s a frame from 0, as a stable run's on macOS (mac_app.m) and the browser's
    // (web/host.js shot_at), each drawn at the next vsync whether the app asks for it or not, until that clock reaches
    // MS; that frame drawn, no other ("SHOT n t" on the log: adb's screencap takes it), and a frame the system asks
    // for after it drawn at the same moment. The clock stands still while the app awaits the host (an image decoding:
    // what its last frame said), so the picture is of the app at MS on its own clock, however fast the machine is.
    // shot_at=rest (Host.shotRest): at the first frame that left nothing that ends to come (@ui's Ctx::at_rest), a
    // failure ("SHOT FAIL") when none has by a minute on its clock.
    private double shotClock;
    private int shotFrames;
    private volatile boolean shotTaken;

    private void shotFrame(float w, float h) {
        double t = shotClock;
        Native.frame(w, h, density, t);
        Script.frameDrawn();
        if (shotTaken) return;
        shotFrames++;
        if (Native.awaiting() > 0) {
            // the clock stands still; the host's answer asks for the next frame
            return;
        }
        if (Host.shotRest && !Native.atRest() && (t >= 60000 || Native.restWhy().startsWith("never: "))) {
            shotTaken = true;
            String why = Native.restWhy();
            Host.log("SHOT FAIL: " + (why.startsWith("never: ") ? "at rest, but " + why.substring(7)
                    : "not at rest after 60 s on its clock: " + why));
            return;
        }
        if (Host.shotRest ? Native.atRest() : t >= Host.shotAt) {
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
        // another view set the drawing up in its own context since this one did (an OverActivity came and went): set
        // up again here, at this view's size
        if (mine != setUp) {
            Native.surfaceCreated();
            MBText.reset();
            Native.resize(getWidth(), getHeight());
            mine = ++setUp;
        }
        // the soft keyboard's height off the bottom (Host.imeBottom, as it moves): the app lays out above it, the
        // surface keeps its size (resizing it with each step of the keyboard's motion would be far too slow)
        float w = getWidth() / density, h = Math.max(1, getHeight() - Host.imeBottom) / density;
        if (Host.shotAt >= 0) {
            shotFrame(w, h);
            return;
        }
        // the vsync's time; a frame the system asked for (a resize) has none, and time never goes back
        long v = vsyncNanos;
        double now = v != 0 ? v / 1e6 : System.nanoTime() / 1e6;
        if (now < lastFrame) now = lastFrame;
        lastFrame = now;
        boolean more = Native.frame(w, h, density, now);
        if (more) wantFrame();
        Script.frameDrawn();
    }

    // ---- vsync ----

    private volatile long vsyncNanos;
    private final AtomicBoolean wanted = new AtomicBoolean();
    private final Choreographer.FrameCallback vsync = t -> {
        vsyncNanos = t;
        wanted.set(false);
        requestRender();
    };
    private final Runnable postVsync = () -> Choreographer.getInstance().postFrameCallback(vsync);

    /** A frame at the next vsync (from any thread). */
    void wantFrame() {
        if (shotTaken) return;
        if (!wanted.compareAndSet(false, true)) return;
        if (Looper.myLooper() == Looper.getMainLooper()) postVsync.run();
        else Host.main.post(postVsync);
    }

    /** Runs r on the GL thread and asks for a frame. */
    void toGL(Runnable r) {
        queueEvent(r);
        wantFrame();
    }

    // ---- input ----

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        int kind;
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: kind = 0; break;
            case MotionEvent.ACTION_MOVE: kind = 1; break;
            case MotionEvent.ACTION_UP: kind = 2; break;
            case MotionEvent.ACTION_CANCEL: kind = 3; break;
            case MotionEvent.ACTION_POINTER_DOWN:
            case MotionEvent.ACTION_POINTER_UP: {
                // a second finger (a pinch): 4 down, 6 up, at its own place; a finger beyond the second is not told
                int i = e.getActionIndex();
                if (i > 1) return true;
                boolean down = e.getActionMasked() == MotionEvent.ACTION_POINTER_DOWN;
                // the first lifted: the one left becomes the first (its moves come as the first's), the pinch ends
                int at = down ? i : (i == 0 ? 0 : 1);
                final float sx = e.getX(at) / density, sy = e.getY(at) / density;
                final double st = e.getEventTime();
                final int sk = down ? 4 : 6;
                toGL(() -> Native.pointer(sk, sx, sy, st));
                return true;
            }
            default: return true;
        }
        // the samples batched into a move (MotionEvent's history) and the event itself, each at its own time
        // (uptime ms, as Compose's PointerInputChange has them)
        final int n = e.getHistorySize();
        final float[] xs = new float[n + 1], ys = new float[n + 1];
        final double[] ts = new double[n + 1];
        for (int i = 0; i < n; i++) {
            xs[i] = e.getHistoricalX(i) / density;
            ys[i] = e.getHistoricalY(i) / density;
            ts[i] = e.getHistoricalEventTime(i);
        }
        xs[n] = e.getX() / density;
        ys[n] = e.getY() / density;
        ts[n] = e.getEventTime();
        final int k = kind;
        if (kind == 0) requestFocus();
        // the second finger's place too, while there is one (a pinch)
        final boolean two = kind == 1 && e.getPointerCount() > 1;
        final float x2 = two ? e.getX(1) / density : 0, y2 = two ? e.getY(1) / density : 0;
        toGL(() -> {
            for (int i = 0; i <= n; i++) Native.pointer(i < n ? 1 : k, xs[i], ys[i], ts[i]);
            if (two) Native.pointer(5, x2, y2, ts[n]);
        });
        return true;
    }

    /** What the clipboard holds, as words, into the focused field (a paste: KEYCODE_PASTE, the keyboard's menu). */
    void paste() {
        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        android.content.ClipData clip = cm.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence t = clip.getItemAt(0).coerceToText(getContext());
        if (t == null || t.length() == 0) return;
        String s = t.toString();
        toGL(() -> Native.text(0, s, 0, 0));
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        if (code == KeyEvent.KEYCODE_PASTE || (code == KeyEvent.KEYCODE_V && e.isCtrlPressed())) {
            if (Host.imeActive) paste();
            return true;
        }
        int k = keyCode(code);
        if (k != 0) {
            int mods = e.isShiftPressed() ? 1 : 0;
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

    MBInput input;

    @Override
    public InputConnection onCreateInputConnection(EditorInfo out) {
        // multi-line, with no action of the keyboard's own: its Enter is a key the field decides on (a new line in
        // still.fail's composer, as its Android app's field does; the demo sends)
        out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
        out.imeOptions = EditorInfo.IME_ACTION_NONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION
                | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        out.initialSelStart = Host.selStart;
        out.initialSelEnd = Host.selEnd;
        input = new MBInput(this);
        return input;
    }

    /**
     * What an input method talks to. Edits go to MoonBit as events; MoonBit
     * owns the text and tells the host the text and selection after each
     * frame (Host.setIme), which is what the queries below answer from.
     */
    static class MBInput extends BaseInputConnection {
        final MBView view;
        volatile boolean composing;
        /** What is being composed (shown at the caret, not yet in MoonBit's text). */
        volatile String composingText = "";

        MBInput(MBView v) {
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
            if (before > 0) view.toGL(() -> Native.key(1, 0));
            if (after > 0) view.toGL(() -> Native.key(2, 0));
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent e) {
            if (e.getAction() != KeyEvent.ACTION_DOWN) return true;
            if (e.getKeyCode() == KeyEvent.KEYCODE_PASTE) { view.paste(); return true; }
            int k = keyCode(e.getKeyCode());
            if (k != 0) {
                int mods = e.isShiftPressed() ? 1 : 0;
                view.toGL(() -> Native.key(k, mods));
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
}
