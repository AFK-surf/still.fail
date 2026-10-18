package dev.mbui;

import android.view.inputmethod.InputConnection;

/**
 * Scripted runs (adb ... --es script ime): taps the composer and drives the
 * view's InputConnection the way an input method does, so screenshots can be
 * taken from adb at fixed times.
 */
final class Script {
    static void start(MBView v) {
        if (!"ime".equals(Host.script)) return;
        float d = v.density;
        Host.main.postDelayed(() -> {
            float x = 100, y = v.getHeight() / d - 30;
            v.post(() -> Native.pointer(0, x, y));
            v.post(() -> Native.pointer(2, x, y));
        }, 2000);
        Host.main.postDelayed(() -> ic(v).setComposingText("ni'hao", 1), 3500);
        Host.main.postDelayed(() -> {
            InputConnection c = ic(v);
            c.commitText("你好", 1);
            c.setComposingText("shi'jie", 1);
            c.commitText("世界，MoonBit 👋", 1);
        }, 6000);
        Host.main.postDelayed(() -> ic(v).performEditorAction(0), 8500);
    }

    static InputConnection ic(MBView v) {
        return v.input != null ? v.input : v.onCreateInputConnection(new android.view.inputmethod.EditorInfo());
    }

    static void frameDrawn() {}
}
