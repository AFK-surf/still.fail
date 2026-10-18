package dev.mbui;

import android.content.Context;
import android.opengl.GLSurfaceView;
import android.text.InputType;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * The surface the MoonBit app draws on. Everything MoonBit runs on the GL
 * thread: frames there, and input is queued onto it.
 */
public class MBView extends GLSurfaceView implements GLSurfaceView.Renderer {
    private static boolean started;  // MoonBit's main runs once per process
    final float density;

    public MBView(Context c) {
        super(c);
        density = c.getResources().getDisplayMetrics().density;
        setEGLContextClientVersion(3);
        setEGLConfigChooser(8, 8, 8, 8, 0, 0);
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
        if (!started) {
            started = true;
            Native.start();
        }
    }

    @Override
    public void onSurfaceChanged(GL10 gl, int w, int h) {
        Native.resize(w, h);
    }

    @Override
    public void onDrawFrame(GL10 gl) {
        float w = getWidth() / density, h = getHeight() / density;
        boolean more = Native.frame(w, h, density, System.nanoTime() / 1e6);
        if (more) requestRender();
        Script.frameDrawn();
    }

    /** Runs r on the GL thread and asks for a frame. */
    void toGL(Runnable r) {
        queueEvent(r);
        requestRender();
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
            default: return true;
        }
        final float x = e.getX() / density, y = e.getY() / density;
        final int k = kind;
        if (kind == 0) requestFocus();
        toGL(() -> Native.pointer(k, x, y));
        return true;
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
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
        out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
        out.imeOptions = EditorInfo.IME_ACTION_SEND | EditorInfo.IME_FLAG_NO_EXTRACT_UI
                | EditorInfo.IME_FLAG_NO_FULLSCREEN;
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
        boolean composing;

        MBInput(MBView v) {
            super(v, false);
            view = v;
        }

        @Override
        public boolean commitText(CharSequence text, int pos) {
            String s = text.toString();
            composing = false;
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
            composing = s.length() > 0;
            view.toGL(() -> Native.text(1, s, s.length(), 0));
            return true;
        }

        @Override
        public boolean finishComposingText() {
            if (composing) {
                composing = false;
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
