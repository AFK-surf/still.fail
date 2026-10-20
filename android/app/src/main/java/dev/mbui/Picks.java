package dev.mbui;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.ext.SdkExtensions;
import android.provider.MediaStore;
import android.provider.OpenableColumns;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Files picked through the system's own pickers (src/host/pick.mbt, as still.fail's Android app's Attach.kt has
 * them): the photo picker (ACTION_PICK_IMAGES where there is one, else the documents UI on images), the documents UI
 * on any file (ACTION_OPEN_DOCUMENT), a photo taken now (ACTION_IMAGE_CAPTURE's picture, as TakePicturePreview). Read
 * off the main thread once picked; MoonBit asks after them each frame (android_host.c).
 */
final class Picks {
    /** An ask: 0 asking, 1 answered, -1 called off or unreadable; what was picked. */
    static final class Ask {
        volatile int state;
        final List<String> names = new ArrayList<>();
        final List<byte[]> bytes = new ArrayList<>();
    }

    static final ConcurrentHashMap<Integer, Ask> asks = new ConcurrentHashMap<>();
    private static int next = 1;
    /** Request codes of the pickers' answers: this and the ask's id. */
    static final int REQUEST = 0x5000;
    private static final long MAX = 1L << 30;

    static synchronized int start(int kind) {
        int id = next++;
        asks.put(id, new Ask());
        String given = android.system.Os.getenv("MBUI_PICK_FILES");
        if (given != null && !given.isEmpty()) {
            // scripted runs (as on macOS): every ask answered at once with these files (paths the app can read, as
            // its own files'), no picker
            new Thread(() -> given(id, given.split("\\|")), "mbui-pick").start();
        } else {
            Host.main.post(() -> open(id, kind));
        }
        return id;
    }

    private static void given(int id, String[] paths) {
        Ask k = asks.get(id);
        if (k == null) return;
        for (String p : paths) {
            java.io.File f = new java.io.File(p);
            try (InputStream in = new java.io.FileInputStream(f)) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[1 << 16];
                for (int r; (r = in.read(buf)) > 0; ) out.write(buf, 0, r);
                synchronized (k) {
                    k.names.add(f.getName());
                    k.bytes.add(out.toByteArray());
                }
            } catch (Exception e) {
                Host.log("pick: " + p + ": " + e);
            }
        }
        done(id, k.names.isEmpty() ? -1 : 1);
    }

    private static void open(int id, int kind) {
        Activity a = Host.activity;
        Intent i;
        if (kind == 1) {
            if (Build.VERSION.SDK_INT >= 33
                    || (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)) {
                i = new Intent(MediaStore.ACTION_PICK_IMAGES);
                i.setType("image/*");
                i.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit());
            } else {
                i = documents("image/*");
            }
        } else if (kind == 2) {
            i = documents("*/*");
        } else {
            i = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        }
        try {
            a.startActivityForResult(i, REQUEST + id);
        } catch (ActivityNotFoundException | NullPointerException e) {
            Host.log("pick: no picker for " + i.getAction() + ": " + e);
            done(id, -1);
        }
    }

    private static Intent documents(String type) {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType(type);
        i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        return i;
    }

    private static void done(int id, int state) {
        Ask k = asks.get(id);
        if (k != null) k.state = state;
        Native.tell(Native.OUTSIDE_PICK, id, state);
    }

    /** MainActivity.onActivityResult: a picker answered. */
    static boolean answered(int request, int result, Intent data) {
        int id = request - REQUEST;
        Ask k = asks.get(id);
        if (k == null) return false;
        if (result != Activity.RESULT_OK || data == null) {
            done(id, -1);
            return true;
        }
        ContentResolver cr = Host.activity.getContentResolver();
        new Thread(() -> {
            List<Uri> uris = new ArrayList<>();
            if (data.getClipData() != null) {
                for (int n = 0; n < data.getClipData().getItemCount(); n++) uris.add(data.getClipData().getItemAt(n).getUri());
            } else if (data.getData() != null) {
                uris.add(data.getData());
            }
            Bitmap photo = uris.isEmpty() && data.getExtras() != null ? (Bitmap) data.getExtras().get("data") : null;
            if (photo != null) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                photo.compress(Bitmap.CompressFormat.JPEG, 90, out);
                synchronized (k) {
                    k.names.add("photo-" + System.currentTimeMillis() + ".jpg");
                    k.bytes.add(out.toByteArray());
                }
            }
            read(cr, k, uris);
            done(id, k.names.isEmpty() ? -1 : 1);
        }, "mbui-pick").start();
        return true;
    }

    /** Each of `uris` read whole into the ask (one over 1 GB left out). */
    private static void read(ContentResolver cr, Ask k, List<Uri> uris) {
        for (Uri u : uris) {
            String name = "file";
            long size = -1;
            try (Cursor c = cr.query(u, new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null)) {
                if (c != null && c.moveToFirst()) {
                    if (!c.isNull(0)) name = c.getString(0);
                    if (!c.isNull(1)) size = c.getLong(1);
                }
            } catch (Exception e) {
                Host.log("pick: " + e);
            }
            if (size > MAX) continue;
            try (InputStream in = cr.openInputStream(u)) {
                if (in == null) continue;
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[1 << 16];
                for (int r; (r = in.read(buf)) > 0; ) {
                    out.write(buf, 0, r);
                    if (out.size() > MAX) break;
                }
                if (out.size() > MAX) continue;
                synchronized (k) {
                    k.names.add(name);
                    k.bytes.add(out.toByteArray());
                }
            } catch (Exception e) {
                Host.log("pick: " + name + ": " + e);
            }
        }
    }

    /** A photo of the gallery (Gallery.java's content:// address) read whole, as a pick of it. */
    static synchronized int photo(String src) {
        if (Host.activity == null) return 0;
        int id = next++;
        Ask k = new Ask();
        asks.put(id, k);
        ContentResolver cr = Host.activity.getContentResolver();
        new Thread(() -> {
            List<Uri> uris = new ArrayList<>();
            uris.add(Uri.parse(src));
            read(cr, k, uris);
            done(id, k.names.isEmpty() ? -1 : 1);
        }, "mbui-pick").start();
        return id;
    }

    static int state(int id) {
        Ask k = asks.get(id);
        return k == null ? -1 : k.state;
    }

    static int count(int id) {
        Ask k = asks.get(id);
        return k == null ? 0 : k.names.size();
    }

    static String name(int id, int i) {
        Ask k = asks.get(id);
        return k == null || i < 0 || i >= k.names.size() ? "" : k.names.get(i);
    }

    static byte[] bytes(int id, int i) {
        Ask k = asks.get(id);
        return k == null || i < 0 || i >= k.bytes.size() ? new byte[0] : k.bytes.get(i);
    }

    static void end(int id) {
        asks.remove(id);
    }
}
