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
    /** The soft keyboard's height over the app's view, in px, as it moves (MainActivity): MBView lays out above it. */
    static volatile int imeBottom;

    /** MBUI_IME_LOG=1: what the input method asks of the field, and what it is told, on the log. */
    static boolean imeLog() { return "1".equals(android.system.Os.getenv("MBUI_IME_LOG")); }

    /** The activity resumed, and its window with the focus (MainActivity): what Native.appState is told. */
    static volatile boolean resumed, focused;

    /** 1 while the app is shown (resumed), | 2 while its window also has the focus (in front). */
    static int appState() {
        return (resumed ? 1 : 0) | (resumed && focused ? 2 : 0);
    }

    /** Tells the app (on the GL thread, before it pauses when the activity does). */
    static void tellAppState() {
        int s = appState();
        if (view != null) view.toGL(() -> Native.appState(s));
    }

    /** The system in night mode (MainActivity: its configuration's uiMode, kept as it changes): @host.system_dark. */
    static volatile boolean systemDark;

    static boolean systemDark() {
        return systemDark;
    }

    /** The app drawn dark or light (@host.set_dark): the system bars' icons light over it or dark, as the Android app's. */
    static void setDark(boolean dark) {
        main.post(() -> {
            if (activity == null) return;
            android.view.WindowInsetsController c = activity.getWindow().getInsetsController();
            if (c == null) return;
            int light = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            c.setSystemBarsAppearance(dark ? 0 : light, light);
            // what shows under the bars (the app's view is inside them): the dark page's ground, else as it was
            android.view.ViewGroup content = activity.findViewById(android.R.id.content);
            if (content != null && content.getChildCount() > 0) {
                content.getChildAt(0).setBackgroundColor(dark ? 0xFF1B1C1F : android.graphics.Color.rgb(245, 245, 247));
            }
        });
    }

    /**
     * Turned sideways for a film (@host.set_sideways, still.fail's Player.kt): landscape asked for (a phone with rotation
     * locked turns too) and the system bars away, a swipe bringing them for a while; off, upright and the bars back.
     */
    static void setSideways(boolean on) {
        main.post(() -> {
            if (activity == null) return;
            android.view.WindowInsetsController c = activity.getWindow().getInsetsController();
            if (c != null) {
                c.setSystemBarsBehavior(android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                if (on) c.hide(android.view.WindowInsets.Type.systemBars());
                else c.show(android.view.WindowInsets.Type.systemBars());
            }
            activity.setRequestedOrientation(on ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    : android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
            log(on ? "sideways: landscape, the system bars away" : "sideways: upright");
        });
    }

    static void requestFrame() {
        if (view != null) view.wantFrame();
    }

    static void wakeAfter(double ms) {
        main.postDelayed(Host::requestFrame, (long) Math.max(1, ms));
    }

    static void setIme(boolean active, double x, double y, double w, double h,
                       String text, int a, int b) {
        boolean was = imeActive;
        boolean cleared = text.isEmpty() && !imeText.isEmpty();
        // MoonBit's text leaves out what the input method is composing (it is at the caret until committed); the input
        // method's view of the field has it in, the selection after it and the composing region on it. Told without it
        // (no composing region), an input method takes its composition as ended and commits what it had composed:
        // Chinese typed through pinyin came out as "ni'hao你好".
        MBView.MBInput in = view != null ? view.input : null;
        String comp = in != null && in.composing ? in.composingText : "";
        int cs = -1, ce = -1;
        if (active && !comp.isEmpty()) {
            int at = Math.max(0, Math.min(Math.min(a, b), text.length()));
            text = text.substring(0, at) + comp + text.substring(at);
            cs = at;
            ce = at + comp.length();
            a = ce;
            b = ce;
        }
        imeActive = active;
        imeText = text;
        selStart = a;
        selEnd = b;
        final int sa = a, sb = b, ca = cs, cb = ce;
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
                    if (imeLog()) log("ime: updateSelection " + sa + "," + sb + " composing " + ca + "," + cb);
                    imm.updateSelection(view, sa, sb, ca, cb);
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

    /**
     * The word of `text` around `off` as the system finds words (ICU's BreakIterator, as Compose's text and the
     * still.fail app's Pick.kt: a dictionary's words in Chinese and Japanese): start × 2³² + end, or -1 when `off` is in
     * no word (a space, a mark).
     */
    static double wordAt(String text, int off) {
        if (text == null || text.isEmpty() || off < 0 || off >= text.length()) return -1;
        android.icu.text.BreakIterator words = android.icu.text.BreakIterator.getWordInstance();
        words.setText(text);
        int end = words.following(off);
        int status = words.getRuleStatus();
        int start = words.previous();
        if (end == android.icu.text.BreakIterator.DONE || start == android.icu.text.BreakIterator.DONE) return -1;
        if (status < android.icu.text.BreakIterator.WORD_NUMBER) return -1;
        return start * 4294967296.0 + end;
    }

    /**
     * A URL handed to the system (ACTION_VIEW: the browser, or the app that takes such links), from a task of its own;
     * false when no activity takes it.
     */
    static boolean openUrl(String url) {
        if (activity == null || url == null || url.isEmpty()) return false;
        android.content.Intent i = new android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url));
        i.addCategory(android.content.Intent.CATEGORY_BROWSABLE);
        i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
        main.post(() -> {
            try {
                activity.startActivity(i);
                log("open-url: " + url);
            } catch (android.content.ActivityNotFoundException e) {
                log("open-url: nothing takes " + url);
            }
        });
        return true;
    }

    /** Whether the app takes back (a page to go back to); MainActivity's callback follows it. */
    static void backEnabled(boolean on) {
        main.post(() -> { if (activity != null) activity.setBackEnabled(on); });
    }

    static void log(String s) {
        java.io.Writer f = logFile;
        if (f != null) {
            synchronized (Host.class) {
                try {
                    f.write(s);
                    f.write('\n');
                    f.flush();
                } catch (java.io.IOException e) {
                    logFile = null;
                }
            }
        }
        Log.i("mbui", s);
    }

    /**
     * MBUI_LOG_FILE=NAME: the log also written, whole, to the app's files/NAME (a run's tape, MBUI_DRAW_LOG and
     * MBUI_TEXT_RECORD: thousands of lines that logcat's ring would drop), each line there before logcat has it.
     * Opened by MainActivity once the environment is set.
     */
    static volatile java.io.Writer logFile;

    static void openLogFile(Context c) {
        String name = android.system.Os.getenv("MBUI_LOG_FILE");
        if (name == null || name.isEmpty() || logFile != null) return;
        try {
            logFile = new java.io.BufferedWriter(new java.io.OutputStreamWriter(
                    new java.io.FileOutputStream(new java.io.File(c.getFilesDir(), name)), "UTF-8"));
        } catch (java.io.IOException e) {
            Log.i("mbui", "MBUI_LOG_FILE " + name + ": " + e);
        }
    }

    static int benchMode() {
        return bench;
    }

    /** Whether the system's animations are off (its animator duration scale 0): motion reduced (src/ui/motion_anim.mbt). */
    static int reduceMotion() {
        MainActivity a = activity;
        if (a == null) return 0;
        float scale = android.provider.Settings.Global.getFloat(a.getContentResolver(), android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        return scale == 0f ? 1 : 0;
    }

    /**
     * A scripted run's input (src/ui/drive.mbt, from the GL thread), sent as an input method sends it: committed
     * words, composed words, Enter and backspace through the view's InputConnection, a paste as KEYCODE_PASTE (the
     * clipboard read there). 0 for what has no path here (4, the window's picture: adb's screencap takes it).
     */
    static int drive(int kind, String text) {
        // a notification of the app's, tapped or looked for by its words (Notices.drive)
        if (kind == 6 || kind == 7) return Notices.drive(kind == 6, text);
        if (kind == 4 || kind > 5) return 0;
        main.post(() -> {
            MBView v = view;
            if (v == null) return;
            android.view.inputmethod.InputConnection ic = Script.ic(v);
            switch (kind) {
                case 0: ic.commitText(text, 1); break;
                case 1: ic.setComposingText(text, 1); break;
                case 2:
                    ic.sendKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER));
                    break;
                case 3:
                    v.dispatchKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_PASTE));
                    break;
                case 5: ic.deleteSurroundingText(1, 0); break;
            }
        });
        return 1;
    }

    static void exit(int code) {
        main.post(() -> {
            activity.finishAndRemoveTask();
            System.exit(code);
        });
    }

    /** Whether java.nio knows `name` (charset.mbt). */
    static boolean charsetKnown(String name) {
        try {
            return java.nio.charset.Charset.isSupported(name);
        } catch (Exception e) {
            return false;
        }
    }

    /** `data` decoded as `name`, a byte it cannot map U+FFFD (charset.mbt). */
    static String charsetDecode(byte[] data, String name) {
        try {
            return new String(data, java.nio.charset.Charset.forName(name));
        } catch (Exception e) {
            return "";
        }
    }
}
