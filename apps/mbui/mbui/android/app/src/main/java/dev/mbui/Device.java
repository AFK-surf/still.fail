package dev.mbui;

import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.ContentResolver;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.Arrays;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * The device beyond the window (src/host/device.mbt; android_device.h calls these): a key catcher's keyboard (the
 * focus with no text of its own: MBView asks catchKey while `catching`), the soft keyboard's height, the clipboard
 * read (its words, its picture made a PNG, as still.fail's ScreenClips.kt: readyImage, asPng, encodePng) and written
 * (words with a label; a PNG kept as a file of the cache's screen-clips, the newest KEEP, that the clip points at
 * through Shares.Files), the screen kept on, haptics.
 */
final class Device {
    /** The focus is a key catcher's (@host.key_catch): MBView's keys and input connection are the catcher's. */
    static volatile boolean catching;

    // ScreenClips.kt's bounds (device.mbt's clip_*_max)
    static final int PNG_MAX = 8 * 1024 * 1024;
    static final int SOURCE_MAX = 32 * 1024 * 1024;
    static final long PIXELS_MAX = 16L * 1024 * 1024;
    /** What a picture on the clipboard is (device.mbt's clip_*). */
    static final int NONE = 0, PNG = 1, TOO_LARGE = 2, UNREADABLE = 3;

    static void keyCatch(boolean on) {
        if (catching == on) return;
        catching = on;
        // the input method's connection made again, as the catcher's (or the field's) now
        if (Host.imeActive) Host.main.post(() -> {
            MBView v = Host.view;
            if (v == null) return;
            InputMethodManager imm = (InputMethodManager) v.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
            imm.restartInput(v);
        });
    }

    /** The soft keyboard over the view's foot, in points (MainActivity's keyboardAt). */
    static double imeInset() {
        MBView v = Host.view;
        return v == null ? 0 : Host.imeBottom / v.density;
    }

    /** Android 13 and later show what was put on the clipboard themselves, with a preview. */
    static boolean copyShown() {
        return Build.VERSION.SDK_INT >= 33;
    }

    /**
     * A key with the focus a catcher's (from a keyboard, or the input method's sendKeyEvent): the framework's code and
     * modifiers (src/ui/desktop.mbt: Shift 1, Ctrl 2, Alt 4, Meta 8), or null for a character typed as text. As
     * still.fail's Input.kt domKey: the named keys; a letter or digit with Ctrl, Alt or Meta held as its key (1000 +
     * the character, lower case), another character with them by itself.
     */
    static int[] catchKey(KeyEvent e) {
        int meta = e.getMetaState();
        int mods = ((meta & KeyEvent.META_SHIFT_ON) != 0 ? 1 : 0) | ((meta & KeyEvent.META_CTRL_ON) != 0 ? 2 : 0)
                | ((meta & KeyEvent.META_ALT_ON) != 0 ? 4 : 0) | ((meta & KeyEvent.META_META_ON) != 0 ? 8 : 0);
        int code;
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_DEL: code = 1; break;
            case KeyEvent.KEYCODE_FORWARD_DEL: code = 2; break;
            case KeyEvent.KEYCODE_DPAD_LEFT: code = 3; break;
            case KeyEvent.KEYCODE_DPAD_RIGHT: code = 4; break;
            case KeyEvent.KEYCODE_DPAD_UP: code = 5; break;
            case KeyEvent.KEYCODE_DPAD_DOWN: code = 6; break;
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: code = 7; break;
            case KeyEvent.KEYCODE_MOVE_HOME: code = 8; break;
            case KeyEvent.KEYCODE_MOVE_END: code = 9; break;
            case KeyEvent.KEYCODE_PAGE_UP: code = 15; break;
            case KeyEvent.KEYCODE_PAGE_DOWN: code = 16; break;
            case KeyEvent.KEYCODE_ESCAPE: code = 17; break;
            case KeyEvent.KEYCODE_TAB: code = 18; break;
            case KeyEvent.KEYCODE_SPACE: code = 1032; break;
            default: code = 0;
        }
        if (code != 0) return new int[] {code, mods};
        if ((mods & (2 | 4 | 8)) == 0) return null;
        int k = e.getKeyCode();
        if (k >= KeyEvent.KEYCODE_A && k <= KeyEvent.KEYCODE_Z) return new int[] {1000 + 'a' + (k - KeyEvent.KEYCODE_A), mods};
        if (k >= KeyEvent.KEYCODE_0 && k <= KeyEvent.KEYCODE_9) return new int[] {1000 + '0' + (k - KeyEvent.KEYCODE_0), mods};
        int ch = e.getUnicodeChar();
        return ch > 0 ? new int[] {1000 + ch, mods} : null;
    }

    // ---- the clipboard read ----

    /** A read: 0 reading, 1 read; its words and its picture. */
    static final class Read {
        volatile int state;
        String text = "";
        int picture = NONE;
        byte[] png = new byte[0];
    }

    static final ConcurrentHashMap<Integer, Read> reads = new ConcurrentHashMap<>();
    private static final AtomicInteger nextRead = new AtomicInteger(1);

    /** The clipboard read: the primary clip taken on the main thread (as the app in front), the rest off it. */
    static int clipRead() {
        int id = nextRead.getAndIncrement();
        Read r = new Read();
        reads.put(id, r);
        Host.main.post(() -> {
            Context c = Host.activity;
            ClipData clip = null;
            try {
                ClipboardManager cm = c == null ? null : (ClipboardManager) c.getSystemService(Context.CLIPBOARD_SERVICE);
                clip = cm == null ? null : cm.getPrimaryClip();
            } catch (Exception e) {
                Host.log("clipboard: " + e);
            }
            final ClipData got = clip != null && clip.getItemCount() > 0 ? clip : null;
            new Thread(() -> {
                if (got != null && c != null) readClip(c, got, r);
                r.state = 1;
                Native.tell(Native.OUTSIDE_CLIP, id, 1);
            }, "mbui-clip-read").start();
        });
        return id;
    }

    /** As still.fail's ScreenViewer.kt paste: the first item's picture (its URI, an image as the clip or its provider
     * says), its words (its text; else, with no picture, what it says as text). */
    private static void readClip(Context c, ClipData clip, Read r) {
        ClipData.Item item = clip.getItemAt(0);
        ClipDescription d = clip.getDescription();
        boolean described = false;
        if (d != null) for (int i = 0; i < d.getMimeTypeCount(); i++) described |= isImage(d.getMimeType(i));
        ContentResolver cr = c.getContentResolver();
        Uri uri = item.getUri();
        Uri image = null;
        if (uri != null) {
            String type = null;
            try {
                type = cr.getType(uri);
            } catch (Exception ignored) {
            }
            if (described || isImage(type)) image = uri;
        }
        CharSequence text = item.getText();
        if (text == null && image == null) {
            try {
                text = item.coerceToText(c);
            } catch (Exception ignored) {
            }
        }
        r.text = text == null ? "" : text.toString();
        if (image != null) readyImage(cr, image, r);
    }

    private static boolean isImage(String type) {
        return type != null && type.trim().toLowerCase().startsWith("image/");
    }

    private static void readyImage(ContentResolver cr, Uri uri, Read r) {
        byte[] bytes;
        try (InputStream in = cr.openInputStream(uri)) {
            if (in == null) {
                r.picture = UNREADABLE;
                return;
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[64 * 1024];
            for (int n; (n = in.read(buf)) >= 0; ) {
                if (out.size() + n > SOURCE_MAX) {
                    r.picture = TOO_LARGE;
                    return;
                }
                out.write(buf, 0, n);
            }
            bytes = out.toByteArray();
        } catch (Exception e) {
            r.picture = UNREADABLE;
            return;
        }
        if (bytes.length == 0) {
            r.picture = UNREADABLE;
            return;
        }
        if (isPng(bytes)) {
            r.picture = bytes.length <= PNG_MAX ? PNG : TOO_LARGE;
            if (r.picture == PNG) r.png = bytes;
            return;
        }
        // another kind (JPEG, WebP, HEIF, a GIF's first frame…) made a PNG; too many pixels are not decoded
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            r.picture = UNREADABLE;
            return;
        }
        if ((long) bounds.outWidth * bounds.outHeight > PIXELS_MAX) {
            r.picture = TOO_LARGE;
            return;
        }
        Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        if (b == null) {
            r.picture = UNREADABLE;
            return;
        }
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            if (!b.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                r.picture = UNREADABLE;
            } else if (out.size() > PNG_MAX) {
                r.picture = TOO_LARGE;
            } else {
                r.picture = PNG;
                r.png = out.toByteArray();
            }
        } finally {
            b.recycle();
        }
    }

    private static final byte[] SIGNATURE = {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10};

    static boolean isPng(byte[] b) {
        return b.length >= SIGNATURE.length && Arrays.equals(Arrays.copyOf(b, SIGNATURE.length), SIGNATURE);
    }

    static int clipState(int id) {
        Read r = reads.get(id);
        return r == null ? -1 : r.state;
    }

    static int clipPicture(int id) {
        Read r = reads.get(id);
        return r == null ? NONE : r.picture;
    }

    static String clipText(int id) {
        Read r = reads.get(id);
        return r == null ? "" : r.text;
    }

    static byte[] clipPng(int id) {
        Read r = reads.get(id);
        return r == null ? new byte[0] : r.png;
    }

    static void clipEnd(int id) {
        reads.remove(id);
    }

    // ---- the clipboard written ----

    /** What was last put there: a PNG still being kept is not put there once another came after it. */
    private static final AtomicInteger copies = new AtomicInteger();

    /** Words (`png` empty) or a PNG put on the clipboard, `label` the clip's. */
    static void clipSet(String text, byte[] png, String label) {
        Context c = Host.activity;
        if (c == null) return;
        int n = copies.incrementAndGet();
        if (png == null || png.length == 0) {
            Host.main.post(() -> setClip(c, ClipData.newPlainText(label, text)));
            return;
        }
        new Thread(() -> {
            File f;
            try {
                f = keep(new File(c.getCacheDir(), Shares.CLIPS), png, System.currentTimeMillis());
            } catch (Exception e) {
                Host.log("clipboard: " + e);
                return;
            }
            Uri uri = new Uri.Builder().scheme("content").authority(c.getPackageName() + ".shared")
                    .appendPath(Shares.CLIPS).appendPath(f.getName()).build();
            Host.main.post(() -> {
                if (n == copies.get()) setClip(c, new ClipData(label, new String[] {"image/png"}, new ClipData.Item(uri)));
            });
        }, "mbui-clip-keep").start();
    }

    private static void setClip(Context c, ClipData clip) {
        try {
            ((ClipboardManager) c.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(clip);
        } catch (Exception e) {
            Host.log("clipboard: " + e);
        }
    }

    /** How many are kept: the one on the clipboard and a couple before it (another app may still be reading one). */
    static final int KEEP = 3;
    private static long last;

    /** `png` kept as a new file in `dir`, named so the newest sorts last; those beyond KEEP deleted, oldest first
     * (still.fail's ScreenClips.keep). */
    static synchronized File keep(File dir, byte[] png, long now) throws java.io.IOException {
        dir.mkdirs();
        // each later than the one before, however quickly they come
        last = Math.max(now, last + 1);
        String stamp = Long.toString(last);
        while (stamp.length() < 15) stamp = "0" + stamp;
        File file = new File(dir, "copied-" + stamp + ".png");
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(png);
        }
        File[] all = dir.listFiles(File::isFile);
        if (all != null && all.length > KEEP) {
            Arrays.sort(all, (a, b) -> a.getName().compareTo(b.getName()));
            for (int i = 0; i < all.length - KEEP; i++) all[i].delete();
        }
        return file;
    }

    // ---- the screen and haptics ----

    static void keepAwake(boolean on) {
        Host.main.post(() -> {
            MainActivity a = Host.activity;
            if (a == null) return;
            if (on) a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        });
    }

    /** device.mbt's haptic_* as the constants Compose's AndroidHapticFeedback performs for them. */
    static void haptic(int kind) {
        int constant;
        switch (kind) {
            case 0: constant = HapticFeedbackConstants.LONG_PRESS; break;
            case 1: constant = HapticFeedbackConstants.CONTEXT_CLICK; break;
            case 2: constant = HapticFeedbackConstants.TEXT_HANDLE_MOVE; break;
            case 3: constant = Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY; break;
            case 4: constant = Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.REJECT : HapticFeedbackConstants.LONG_PRESS; break;
            case 5: constant = HapticFeedbackConstants.KEYBOARD_TAP; break;
            default: return;
        }
        Host.main.post(() -> {
            MBView v = Host.view;
            if (v != null) v.performHapticFeedback(constant);
        });
    }
}
