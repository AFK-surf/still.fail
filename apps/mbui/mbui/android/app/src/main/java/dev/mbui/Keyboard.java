package dev.mbui;

import android.content.res.Configuration;
import android.inputmethodservice.InputMethodService;
import android.os.SystemClock;
import android.system.Os;
import android.text.InputType;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.FrameLayout;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * The app as the system's keyboard (an input method other apps type with): the app's own MoonBit program, told it is
 * one (MBUI_KEYBOARD=1, before it starts: the app's main runs its keyboard instead of itself), drawn in the input
 * method's window. In a process of its own (the app's manifest declares this service with android:process), so the app
 * and its keyboard each have their program, as two apps would; the keyboard's process starts nothing of the app's.
 *
 * What the keyboard is given: its files (the APK's assets/keyboard, copied to the app's files/keyboard as the APK
 * changes; MBUI_KEYBOARD_DIR, where it also keeps its own), and on channel "keyboard" (@ui.on_message):
 * - {"start": {"action": "send"|"search"|"go"|"done"|"next"|"enter", "kind": "text"|"number"|"phone"|"password"|
 *   "email"|"url"}}: a field to type into (the field's Enter, and what it takes)
 * - {"finish": true}: the keyboard put away
 * - {"touch": {"id": n, "kind": "down"|"move"|"up"|"cancel", "x": dp, "y": dp}}: every finger on it, each its own
 *   (a keyboard is typed with two thumbs, one key down before the other is up), besides the first finger's usual
 *   pointer the program's widgets take (its bar's)
 * What it asks (@ui.native_call): "keyboard.commit" {"text"} into the field; "keyboard.delete" (what is before the
 * caret, a character); "keyboard.enter" (the field's action, or a new line); "keyboard.hide"; "keyboard.switch" (the
 * next input method).
 */
public class Keyboard extends InputMethodService {
    /** The keyboard's height without the bars at its foot, as a share of its width (src/keyboard/keys.mbt: WeChat's
     *  keyboard's 788 units over 1080). */
    static final float HEIGHT_OF_WIDTH = 788f / 1080f;

    private MBView view;
    private float density;
    private int insetPx = -1;

    @Override
    public void onCreate() {
        super.onCreate();
        density = getResources().getDisplayMetrics().density;
        try {
            Os.setenv("MBUI_KEYBOARD", "1", true);
            Os.setenv("MBUI_KEYBOARD_DIR", files().getAbsolutePath(), true);
        } catch (android.system.ErrnoException e) {
            Host.log("keyboard env: " + e);
        }
        Host.systemDark = night(getResources().getConfiguration());
        Host.fontScale = getResources().getConfiguration().fontScale;
        Natives.put("keyboard.commit", (params, reply) -> {
            String text;
            try {
                text = new JSONObject(params).optString("text", "");
            } catch (JSONException e) {
                reply.fail("no text");
                return;
            }
            Host.main.post(() -> {
                InputConnection ic = getCurrentInputConnection();
                if (ic != null) ic.commitText(text, 1);
            });
            reply.ok("{}");
        });
        Natives.put("keyboard.delete", (params, reply) -> {
            Host.main.post(() -> {
                InputConnection ic = getCurrentInputConnection();
                if (ic == null) return;
                CharSequence sel = ic.getSelectedText(0);
                if (sel != null && sel.length() > 0) ic.commitText("", 1);
                // (the key event, not deleteSurroundingText: the field takes a whole emoji, a surrogate pair, at once)
                else sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL);
            });
            reply.ok("{}");
        });
        Natives.put("keyboard.enter", (params, reply) -> {
            Host.main.post(this::enter);
            reply.ok("{}");
        });
        Natives.put("keyboard.hide", (params, reply) -> {
            Host.main.post(() -> requestHideSelf(0));
            reply.ok("{}");
        });
        Natives.put("keyboard.switch", (params, reply) -> {
            Host.main.post(() -> {
                if (!switchToNextInputMethod(false)) {
                    android.view.inputmethod.InputMethodManager imm = (android.view.inputmethod.InputMethodManager)
                            getSystemService(INPUT_METHOD_SERVICE);
                    imm.showInputMethodPicker();
                }
            });
            reply.ok("{}");
        });
    }

    private static boolean night(Configuration c) {
        return (c.uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    }

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        Host.systemDark = night(c);
        Host.fontScale = c.fontScale;
    }

    /** The keyboard's files: the APK's assets/keyboard copied here once for each install or update of the APK. */
    private File files() {
        File dir = new File(getFilesDir(), "keyboard");
        dir.mkdirs();
        long installed;
        try {
            installed = getPackageManager().getPackageInfo(getPackageName(), 0).lastUpdateTime;
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {
            installed = 0;
        }
        File stamp = new File(dir, ".copied");
        String want = Long.toString(installed);
        try {
            if (stamp.exists() && want.equals(new String(java.nio.file.Files.readAllBytes(stamp.toPath()),
                    StandardCharsets.UTF_8))) {
                return dir;
            }
            String[] names = getAssets().list("keyboard");
            if (names != null) {
                for (String name : names) {
                    File to = new File(dir, name + ".new");
                    try (InputStream in = getAssets().open("keyboard/" + name);
                         FileOutputStream out = new FileOutputStream(to)) {
                        byte[] buf = new byte[1 << 16];
                        for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
                    }
                    if (!to.renameTo(new File(dir, name))) Host.log("keyboard: " + name + " not put in place");
                }
            }
            try (FileOutputStream out = new FileOutputStream(stamp)) {
                out.write(want.getBytes(StandardCharsets.UTF_8));
            }
        } catch (java.io.IOException e) {
            Host.log("keyboard files: " + e);
        }
        return dir;
    }

    @Override
    public View onCreateInputView() {
        FrameLayout root = new FrameLayout(this);
        view = new MBView(this) {
            @Override
            public boolean onTouchEvent(MotionEvent e) {
                touches(e);
                return super.onTouchEvent(e);
            }
        };
        Host.view = view;
        root.addView(view, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height()));
        // the navigation bar (or the gesture's handle, and the system's own keys for a keyboard: put away, the next
        // input method) under the keys, on the keyboard's ground at its foot (src/keyboard/view.mbt Paint's foot): the
        // view stops above it, so that what the system draws there is not under the view's surface
        root.setBackgroundColor(Host.systemDark ? 0xFF262626 : 0xFFD5D7DD);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.navigationBars());
            // (with gestures, the system draws its keyboard keys in a frame taller than the handle's inset says)
            int foot = Math.max(bars.bottom, navFrame());
            if (foot != insetPx) {
                insetPx = foot;
                root.setPadding(0, 0, 0, insetPx);
            }
            return insets;
        });
        return root;
    }

    /** The height of the navigation bar's frame, in px, where the system draws its keys for a keyboard (put it away,
     *  the next input method) with gesture navigation; 0 where the system says none. */
    private int navFrame() {
        if (navigationMode() != 2) return 0;
        int id = getResources().getIdentifier("navigation_bar_frame_height", "dimen", "android");
        return id == 0 ? 0 : getResources().getDimensionPixelSize(id);
    }

    /** The system's navigation mode (0 three buttons, 1 two, 2 gestures), as its settings say. */
    private int navigationMode() {
        int id = getResources().getIdentifier("config_navBarInteractionMode", "integer", "android");
        return id == 0 ? 0 : getResources().getInteger(id);
    }

    /** The keyboard's height without the bars at its foot, in px, for the screen's width now. */
    private int height() {
        return Math.round(getResources().getDisplayMetrics().widthPixels * HEIGHT_OF_WIDTH);
    }

    /** Each finger's down, move and up, said to the keyboard (above), in dp from the view's corner. */
    private void touches(MotionEvent e) {
        int action = e.getActionMasked();
        if (action == MotionEvent.ACTION_MOVE) {
            for (int i = 0; i < e.getPointerCount(); i++) touch(e.getPointerId(i), "move", e.getX(i), e.getY(i));
            return;
        }
        String kind;
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: kind = "down"; break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP: kind = "up"; break;
            case MotionEvent.ACTION_CANCEL: kind = "cancel"; break;
            default: return;
        }
        if (action == MotionEvent.ACTION_CANCEL) {
            for (int i = 0; i < e.getPointerCount(); i++) touch(e.getPointerId(i), kind, e.getX(i), e.getY(i));
            return;
        }
        int i = e.getActionIndex();
        touch(e.getPointerId(i), kind, e.getX(i), e.getY(i));
    }

    private void touch(int id, String kind, float x, float y) {
        say("{\"touch\":{\"id\":" + id + ",\"kind\":\"" + kind + "\",\"x\":" + (x / density) + ",\"y\":"
                + (y / density) + "}}");
    }

    private void say(String json) {
        byte[] b = json.getBytes(StandardCharsets.UTF_8);
        if (view != null) view.toGL(() -> Native.postBytes("keyboard", b));
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        Host.view = view;
        Host.resumed = true;
        Host.focused = true;
        Host.tellAppState();
        if (view != null) view.onResume();
        say("{\"start\":{\"action\":\"" + action(info) + "\",\"kind\":\"" + kind(info) + "\"}}");
    }

    @Override
    public void onFinishInputView(boolean finishing) {
        super.onFinishInputView(finishing);
        say("{\"finish\":true}");
        Host.resumed = false;
        Host.tellAppState();
    }

    /** What the field's Enter does, as its EditorInfo says (a field of several lines: a new line). */
    private static String action(EditorInfo info) {
        if ((info.inputType & InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0
                || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) {
            return "enter";
        }
        switch (info.imeOptions & EditorInfo.IME_MASK_ACTION) {
            case EditorInfo.IME_ACTION_SEND: return "send";
            case EditorInfo.IME_ACTION_SEARCH: return "search";
            case EditorInfo.IME_ACTION_GO: return "go";
            case EditorInfo.IME_ACTION_DONE: return "done";
            case EditorInfo.IME_ACTION_NEXT: return "next";
            default: return "enter";
        }
    }

    /** What the field takes, as its EditorInfo says. */
    private static String kind(EditorInfo info) {
        int cls = info.inputType & InputType.TYPE_MASK_CLASS;
        int var = info.inputType & InputType.TYPE_MASK_VARIATION;
        if (cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_DATETIME) return "number";
        if (cls == InputType.TYPE_CLASS_PHONE) return "phone";
        if (cls == InputType.TYPE_CLASS_TEXT) {
            if (var == InputType.TYPE_TEXT_VARIATION_PASSWORD || var == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                    || var == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD) return "password";
            if (var == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                    || var == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS) return "email";
            if (var == InputType.TYPE_TEXT_VARIATION_URI) return "url";
        }
        return "text";
    }

    /** The field's Enter: its action, or a new line. */
    private void enter() {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) return;
        EditorInfo info = getCurrentInputEditorInfo();
        String a = info == null ? "enter" : action(info);
        if (!a.equals("enter")) {
            ic.performEditorAction(info.imeOptions & EditorInfo.IME_MASK_ACTION);
        } else {
            long now = SystemClock.uptimeMillis();
            ic.sendKeyEvent(new KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER, 0));
            ic.sendKeyEvent(new KeyEvent(now, now, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER, 0));
        }
    }

    @Override
    public boolean onEvaluateFullscreenMode() {
        // (never the whole screen, sideways too: the field stays where the person sees it)
        return false;
    }
}
