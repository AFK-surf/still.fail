package dev.mbui;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.inputmethod.InputMethodManager;

/** What the C host calls back into Java for (from the GL thread). */
final class Host {
    static MainActivity activity;
    static MBView view;
    static String script;
    static int bench;
    static final Handler main = new Handler(Looper.getMainLooper());

    // the focused field's text and selection, for the input method
    static volatile boolean imeActive;
    static volatile String imeText = "";
    static volatile int selStart, selEnd;

    static void requestFrame() {
        if (view != null) view.requestRender();
    }

    static void wakeAfter(double ms) {
        main.postDelayed(Host::requestFrame, (long) Math.max(1, ms));
    }

    static void setIme(boolean active, double x, double y, double w, double h,
                       String text, int a, int b) {
        boolean was = imeActive;
        boolean cleared = text.length() < imeText.length() && text.isEmpty();
        imeActive = active;
        imeText = text;
        selStart = a;
        selEnd = b;
        main.post(() -> {
            InputMethodManager imm = (InputMethodManager)
                    activity.getSystemService(Context.INPUT_METHOD_SERVICE);
            if (active && !was) {
                view.requestFocus();
                imm.restartInput(view);
                imm.showSoftInput(view, 0);
            } else if (!active && was) {
                imm.hideSoftInputFromWindow(view.getWindowToken(), 0);
            } else if (active) {
                if (cleared && (view.input == null || !view.input.composing)) {
                    imm.restartInput(view);
                } else {
                    imm.updateSelection(view, a, b, -1, -1);
                }
            }
        });
    }

    static void clipboardSet(String s) {
        main.post(() -> {
            ClipboardManager cm = (ClipboardManager)
                    activity.getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("text", s));
        });
    }

    static void log(String s) {
        Log.i("mbui", s);
    }

    static int benchMode() {
        return bench;
    }

    static void exit(int code) {
        main.post(() -> {
            activity.finishAndRemoveTask();
            System.exit(code);
        });
    }
}
