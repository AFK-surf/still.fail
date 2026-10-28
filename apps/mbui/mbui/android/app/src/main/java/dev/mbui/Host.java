package dev.mbui;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.InputDevice;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inputmethod.InputMethodManager;

/** What the C host calls back into Java for (from the GL thread). */
final class Host {
    static MainActivity activity;
    static MBView view;
    static String script;
    static int bench;
    /** A picture at a declared moment (--ei shot_at MS; -1: none): MBView's frames on a clock of their own. */
    static int shotAt = -1;
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

    /** The system in night mode (MainActivity: its configuration's uiMode, kept as it changes): @hostapi.system_dark. */
    static volatile boolean systemDark;
    /** The system's size of words (MainActivity: its configuration's fontScale, kept as it changes): @hostapi.font_scale. */
    static volatile float fontScale = 1f;

    static float fontScale() {
        return fontScale;
    }

    /** What the app was started to be used with (@hostapi.native_pointing): keyboard and mouse (2) where a mouse or a
     * touchpad is among the input devices as it starts (DeX, ChromeOS, a mouse plugged in), else touch (1). */
    static int nativePointing() {
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d == null || d.isVirtual()) continue;
            if (d.supportsSource(InputDevice.SOURCE_MOUSE) || d.supportsSource(InputDevice.SOURCE_TOUCHPAD)) return 2;
        }
        return 1;
    }

    /** Whether a keyboard is at hand now (@hostapi.keyboard): a physical keyboard of letters among the input devices (1;
     * not the on-screen one), else 0. Asked as what says keys is drawn; a frame asked for as a device comes or goes, so
     * they are said, or not, at once. */
    static int keyboard() {
        watchDevices();
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d == null || d.isVirtual()) continue;
            if (d.supportsSource(InputDevice.SOURCE_KEYBOARD) && d.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC) return 1;
        }
        return 0;
    }

    private static boolean watching;

    /** A frame asked for as an input device comes, goes or changes (InputManager's listener, on the main thread). */
    private static void watchDevices() {
        if (watching || view == null) return;
        watching = true;
        android.hardware.input.InputManager im = view.getContext().getSystemService(android.hardware.input.InputManager.class);
        if (im == null) return;
        main.post(() -> im.registerInputDeviceListener(new android.hardware.input.InputManager.InputDeviceListener() {
            @Override public void onInputDeviceAdded(int id) { requestFrame(); }
            @Override public void onInputDeviceRemoved(int id) { requestFrame(); }
            @Override public void onInputDeviceChanged(int id) { requestFrame(); }
        }, main));
    }

    /** Whether a service reads the screen (@hostapi.a11y_on; A11y.on). */
    static boolean a11yOn() {
        return A11y.on();
    }

    /** What the app's widgets are now (@hostapi.a11y_tree, from the GL thread): the view's virtual nodes made of it. */
    static void a11yTree(String lines) {
        main.post(() -> {
            MBView v = view;
            if (v != null) v.a11y().set(lines);
        });
    }

    static boolean systemDark() {
        return systemDark;
    }

    /** What shows under the system bars (the app's view is inside them), light and dark: MainActivity's dev.mbui.ground. */
    static int groundLight = android.graphics.Color.rgb(245, 245, 247), groundDark = 0xFF1B1C1F;

    /** The app drawn dark or light (@hostapi.set_dark): the system bars' icons light over it or dark, as the Android app's. */
    static void setDark(boolean dark) {
        main.post(() -> {
            if (activity == null) return;
            android.view.WindowInsetsController c = activity.getWindow().getInsetsController();
            if (c == null) return;
            int light = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            c.setSystemBarsAppearance(dark ? 0 : light, light);
            // what shows under the bars (the app's view is inside them): the dark page's ground, else as it was; none
            // over another app
            android.view.ViewGroup content = activity.findViewById(android.R.id.content);
            if (content != null && content.getChildCount() > 0 && !activity.over()) {
                content.getChildAt(0).setBackgroundColor(dark ? groundDark : groundLight);
            }
        });
    }

    /**
     * Turned sideways for a film (@hostapi.set_sideways, still.fail's Player.kt): landscape asked for (a phone with rotation
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
            sideways = on;
            if (on) activity.setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            else holdUpright(activity);
            log(on ? "sideways: landscape, the system bars away" : "sideways: upright");
        });
    }

    /** Whether the app has turned the device sideways itself (setSideways), main thread. */
    static boolean sideways;

    /**
     * A phone held upright only let turn as the person holds it (@hostapi.set_turnable, a station's screen looked at):
     * the user's rotation, so with the rotation lock on the system offers its turn button as the phone is turned (it
     * offers none to a fixed portrait); off, upright only again. Whether the device is one held upright (a phone).
     */
    static boolean setTurnable(boolean on) {
        android.app.Activity a = activity;
        boolean phone = a != null && upright(a.getResources().getConfiguration())
                == android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
        main.post(() -> {
            turnable = on;
            if (activity != null) holdUpright(activity);
        });
        return phone;
    }

    /** Whether the app lets a phone turn as it is held (setTurnable), main thread. */
    static boolean turnable;

    /**
     * Which way the activity asks to be held while the app has not turned it (setSideways off): a phone upright only
     * (a touch device whose short side is under 600 dp: a phone, a fold's outer screen), a tablet or an opened fold's
     * inner screen as the person turns it. Android 16 lets a large screen ignore it, as is meant.
     */
    static int upright(android.content.res.Configuration c) {
        return c.smallestScreenWidthDp < 600 ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                : android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
    }

    /**
     * The activity's held way set again as its screen may have changed (made, a fold opened or closed), or as the app
     * lets it turn or not (setTurnable), unless sideways.
     */
    static void holdUpright(android.app.Activity a) {
        if (sideways) return;
        a.setRequestedOrientation(turnable ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_USER
                : upright(a.getResources().getConfiguration()));
    }

    // The soft keyboard asked for and not shown yet (main thread). A show asked before the window has the focus, or
    // before the keyboard's window can be moved by this one (its insets control: the IME's window made, as after the
    // system's boot), is let go by the system; owed until both, each told as it comes (windowFocused, and the insets
    // controller's controllable types), then asked.
    private static boolean imeOwed;
    /** The soft keyboard shown, as the insets last said (MainActivity). */
    static boolean imeVisible;
    /** The app asked for the keyboard and it has not shown since: a hiding seen meanwhile is the one before the
     *  asking (the app's own, still under way), not the person putting it away (MainActivity's text 7). Set as
     *  imeActive is, on the app's thread, so the two never disagree. */
    static volatile boolean imeAwaited;
    /** Fingers lifted off the view (MBView, main thread), and as many as setIme had seen. */
    static int lifts;
    private static int liftsSeen;
    private static boolean imeControllable;
    private static android.view.View imeWatched;  // the view whose controller tells them (an activity made anew: anew)

    /** The window has the focus or lost it (MainActivity.onWindowFocusChanged): what is owed asked for, and said
     * ("IME owed: show" asked now, "waiting" on the keyboard's window, "none"; scripts/android-keyboard.sh's word). */
    static void windowFocused(boolean has) {
        if (!has) return;
        boolean owed = imeOwed;
        showOwedIme();
        log("IME owed: " + (!owed ? "none" : imeOwed ? "waiting" : "show"));
    }

    private static void showOwedIme() {
        if (!imeOwed || view == null) return;
        if (android.os.Build.VERSION.SDK_INT < 30) {
            if (!view.hasWindowFocus()) return;
            imeOwed = false;
            ((InputMethodManager) activity.getSystemService(Context.INPUT_METHOD_SERVICE)).showSoftInput(view, 0);
            return;
        }
        WindowInsetsController c = view.getWindowInsetsController();
        if (c == null) return;
        if (imeWatched != view) {
            imeWatched = view;
            imeControllable = false;
            c.addOnControllableInsetsChangedListener((ctl, types) -> {
                imeControllable = (types & WindowInsets.Type.ime()) != 0;
                boolean owed = imeOwed;
                showOwedIme();
                if (owed && !imeOwed) log("IME owed: show");
            });
        }
        if (!view.hasWindowFocus()) return;
        // (the controllable types told as they change: none told yet, the listener's first call, at once, says them)
        if (!imeControllable) return;
        imeOwed = false;
        c.show(WindowInsets.Type.ime());
    }

    static void requestFrame() {
        if (view != null) view.wantFrame();
    }

    /**
     * The frame `ms` after the one being built (its time, the vsync's), else after now: drawn at the first vsync at or
     * past it (MBView.wakeAt), asked for two display frames before.
     */
    static void wakeAfter(double ms) {
        MBView v = view;
        if (v == null) return;
        double base = v.buildingFor >= 0 ? v.buildingFor : System.nanoTime() / 1e6;
        double at = base + ms;
        if (v.wakeFor >= 0 && v.wakeFor <= at) return;
        v.wakeFor = at;
        double lead = at - System.nanoTime() / 1e6 - 2 * v.framePeriodMs();
        main.postDelayed(() -> v.wakeAt(at), (long) Math.max(0, lead));
    }

    /** The input method's edits sent to MoonBit (MBView.MBInput.edited, main thread) and taken by it (GL thread). */
    static int imeSent;
    static volatile int imeTaken;

    static void setIme(boolean active, double x, double y, double w, double h,
                       String text, int a, int b) {
        boolean was = imeActive;
        boolean cleared = text.isEmpty() && !imeText.isEmpty();
        // (MoonBit's words, what is composed left out: what a connection made anew starts from, MBView.MBInput)
        imeActive = active;
        if (active != was) imeAwaited = active;
        imeText = text;
        selStart = a;
        selEnd = b;
        // the input method's edits MoonBit had taken when it said this: said before it took them all, it is not its
        // own change but what it had before them (the field's state here is newer)
        final int taken = imeTaken;
        main.post(() -> {
            InputMethodManager imm = (InputMethodManager)
                    activity.getSystemService(Context.INPUT_METHOD_SERVICE);
            boolean lifted = lifts != liftsSeen;
            liftsSeen = lifts;
            if (active && !was) {
                view.requestFocus();
                imm.restartInput(view);
                imeOwed = true;
                showOwedIme();
            } else if (!active && was) {
                imeOwed = false;
                imm.hideSoftInputFromWindow(view.getWindowToken(), 0);
            } else if (active) {
                // the field it has tapped again with no keyboard up (one that did not come, or went): asked for again,
                // as Compose's tap on a focused field shows it (the app says its field anew on such a tap)
                if (lifted && !imeVisible && !imeOwed) {
                    imeOwed = true;
                    imeAwaited = true;
                    showOwedIme();
                }
                MBView.MBInput in = view.input;
                if (in == null || taken != imeSent || !in.took(text, a, b)) return;
                // MoonBit changed the field itself: its words cleared (sent) as a TextView's set anew, the input
                // method started over; else told where the selection is now
                if (cleared) {
                    imm.restartInput(view);
                } else {
                    if (imeLog()) log("ime: updateSelection " + a + "," + b + " (the app's)");
                    imm.updateSelection(view, a, b, -1, -1);
                }
            }
        });
    }

    /**
     * The system's floating text menu over a field's words (@hostapi.text_menu: ActionMode.TYPE_FLOATING), at the
     * rectangle given in dp, offering what {@code can} says (1 cut, 2 copy, 4 paste, 8 select all); or put away.
     */
    static void textMenu(boolean shown, double x, double y, double w, double h, int can) {
        main.post(() -> {
            if (view != null) view.textMenu(shown, x, y, w, h, can);
        });
    }

    static void clipboardSet(String s) {
        main.post(() -> {
            ClipboardManager cm = (ClipboardManager)
                    activity.getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("text", s));
        });
    }

    /** The last secret put on the clipboard (clipboardSecret), till it is taken off (clipboardSecretOff). */
    static String secretCopied;

    /**
     * A secret on the clipboard (@hostapi.clipboard_set_secret, still.fail's Vault.kt copy): marked sensitive (the
     * system's preview of it masked, Android 13 on: ClipDescription.EXTRA_IS_SENSITIVE, by its value, which older
     * systems pass over). The app takes it off `clearMs` later (clipboardSecretOff).
     */
    static void clipboardSecret(String s, double clearMs) {
        main.post(() -> {
            if (activity == null) return;
            ClipboardManager cm = (ClipboardManager) activity.getApplicationContext().getSystemService(Context.CLIPBOARD_SERVICE);
            ClipData clip = ClipData.newPlainText("text", s);
            android.os.PersistableBundle extras = new android.os.PersistableBundle();
            extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
            clip.getDescription().setExtras(extras);
            cm.setPrimaryClip(clip);
            secretCopied = s;
        });
    }

    /**
     * The last secret copied taken off (@hostapi.clipboard_secret_off) unless something else was copied since (when the
     * clipboard cannot be read, the app not in front, it is taken off all the same: a secret left there is worse).
     */
    static void clipboardSecretOff() {
        main.post(() -> {
            String s = secretCopied;
            secretCopied = null;
            if (s == null || activity == null) return;
            ClipboardManager cm = (ClipboardManager) activity.getApplicationContext().getSystemService(Context.CLIPBOARD_SERVICE);
            String now = null;
            try {
                ClipData c = cm.getPrimaryClip();
                if (c != null && c.getItemCount() > 0 && c.getItemAt(0).getText() != null) now = c.getItemAt(0).getText().toString();
            } catch (RuntimeException e) {
                // not readable now (the app not in front)
            }
            if (now == null || now.equals(s)) {
                try {
                    cm.clearPrimaryClip();
                } catch (RuntimeException e) {
                    log("clipboard: not cleared: " + e);
                }
            }
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

    /**
     * The app over another app done (@hostapi.over_done, OverActivity): it ends, back to the app it was over; `openApp`, on
     * into the app's own activity (its task brought to the front) as it ends.
     */
    static void overDone(boolean openApp) {
        main.post(() -> {
            MainActivity a = activity;
            if (!(a instanceof OverActivity)) return;
            if (openApp) {
                a.startActivity(new android.content.Intent(a, MainActivity.class)
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK));
            }
            a.finish();
        });
    }

    /**
     * Whether the app takes back (a page to go back to): the process's, as the app's pages are, told only as it changes.
     * Each activity follows it as it comes to the front (MainActivity.onResume): one made again (the system remade it,
     * an OverActivity was the host meanwhile) took back from nothing it was told, and the system's back left the app
     * from a page with one to go back to.
     */
    static volatile boolean backWanted;

    static void backEnabled(boolean on) {
        backWanted = on;
        main.post(() -> { if (activity != null) activity.setBackEnabled(backWanted); });
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
