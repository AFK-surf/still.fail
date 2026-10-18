package dev.mbui;

import android.view.inputmethod.InputConnection;

/**
 * Scripted runs (adb ... --es script ime): taps the composer and drives the
 * view's InputConnection the way an input method does, so screenshots can be
 * taken from adb at fixed times.
 */
final class Script {
    static boolean ran;

    static void start(MBView first) {
        if (!"ime".equals(Host.script) || ran) return;
        ran = true;
        Host.log("script ime: start");
        // always act on the current view: the activity may have been recreated
        Host.main.postDelayed(() -> {
            MBView v = Host.view;
            float x = 100, y = v.getHeight() / v.density - 30;
            Host.log("script ime: tap composer at " + x + "," + y);
            v.toGL(() -> Native.pointer(0, x, y));
            v.toGL(() -> Native.pointer(2, x, y));
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
}
