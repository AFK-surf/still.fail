package dev.mbui;

import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.inputmethod.InputConnection;

/**
 * Scripted runs (adb ... --es script ime): taps the composer and drives the
 * view's InputConnection the way an input method does, so screenshots can be
 * taken from adb at fixed times.
 */
final class Script {
    static boolean ran;

    static void start(MBView first) {
        if ("fling".equals(Host.script) && !ran) {
            ran = true;
            flings();
            return;
        }
        if (!"ime".equals(Host.script) || ran) return;
        ran = true;
        Host.log("script ime: start");
        // always act on the current view: the activity may have been recreated
        Host.main.postDelayed(() -> {
            MBView v = Host.view;
            float x = 100, y = v.getHeight() / v.density - 30;
            Host.log("script ime: tap composer at " + x + "," + y);
            double t = android.os.SystemClock.uptimeMillis();
            v.toGL(() -> Native.pointer(0, x, y, t));
            v.toGL(() -> Native.pointer(2, x, y, t));
        }, 2000);
        Host.main.postDelayed(() -> ic(Host.view).setComposingText("ni'hao", 1), 3500);
        Host.main.postDelayed(() -> {
            InputConnection c = ic(Host.view);
            c.commitText("你好", 1);
            c.setComposingText("shi'jie", 1);
            c.commitText("世界，MoonBit 👋", 1);
        }, 6000);
        Host.main.postDelayed(() -> ic(Host.view).performEditorAction(0), 8500);
    }

    static InputConnection ic(MBView v) {
        return v.input != null ? v.input : v.onCreateInputConnection(new android.view.inputmethod.EditorInfo());
    }

    static void frameDrawn() {}

    /**
     * Scripted flings (--es script fling, scripts/android.sh fling-test): swipes at set speeds, delivered as the
     * system delivers a finger's: a move each 16 ms frame carrying the digitizer's samples at 4 ms as its history,
     * each sample at its own time, whenever the main thread gets to it. (adb's `input swipe` on a loaded emulator
     * injects too slowly to say how fast a swipe was.) In dp: from y0 to y1 in `ms`, held `hold` ms, let go.
     */
    static void flings() {
        long t = SystemClock.uptimeMillis() + 4000;
        t = swipe(t, 700, 400, 100, 0) + 3500;    // 3 dp/ms up the list
        t = swipe(t, 650, 500, 100, 0) + 3000;    // 1.5 dp/ms
        t = swipe(t, 750, 350, 80, 0) + 4500;     // 5 dp/ms
        t = swipe(t, 200, 750, 80, 0) + 4000;     // 6.9 dp/ms back down, into the top
        t = swipe(t, 300, 600, 600, 300) + 3000;  // pulled past the top, held, let go
        Host.main.postAtTime(() -> Host.log("script fling: done"), t);
    }

    static long swipe(long start, float y0, float y1, long ms, long hold) {
        float d = Host.view.density;
        Host.main.postAtTime(() -> send(MotionEvent.obtain(start, start, MotionEvent.ACTION_DOWN, midX(), y0 * d, 0)), start);
        long end = start + ms;
        for (long prev = start; prev < end; prev += 16) {
            final long from = prev, frame = Math.min(prev + 16, end);
            Host.main.postAtTime(() -> {
                MotionEvent e = null;
                float x = midX();
                for (long s = from + 4; s <= frame; s += 4) {
                    float y = (y0 + (y1 - y0) * (s - start) / (float) ms) * d;
                    if (e == null) e = MotionEvent.obtain(start, s, MotionEvent.ACTION_MOVE, x, y, 0);
                    else e.addBatch(s, x, y, 1f, 1f, 0);
                }
                if (e != null) send(e);
            }, frame);
        }
        long up = end + hold;
        Host.main.postAtTime(() -> send(MotionEvent.obtain(start, up, MotionEvent.ACTION_UP, midX(), y1 * d, 0)), up);
        return up;
    }

    static float midX() {
        return Host.view.getWidth() / 2f;
    }

    static void send(MotionEvent e) {
        Host.view.dispatchTouchEvent(e);
        e.recycle();
    }
}
