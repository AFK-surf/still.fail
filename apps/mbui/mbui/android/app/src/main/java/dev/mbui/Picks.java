package dev.mbui;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
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
 * Files picked through the system's own pickers (src/hostapi/pick.mbt, as still.fail's Android app's Attach.kt has
 * them): the photo picker on photos and videos (ACTION_PICK_IMAGES where there is one, else the documents UI on
 * images and videos), the documents UI on any file (ACTION_OPEN_DOCUMENT), a photo taken now (ACTION_IMAGE_CAPTURE's
 * photo whole, written into the cache's camera/; its small preview where a camera answers only that). Read off the
 * main thread once picked; MoonBit asks after them each frame (android_host.c). One bigger than WHOLE (a video) is not read whole but held by its address (Held): the app's core
 * reads it a part at a time as it goes up ({@link #read}, {@link #hash}, {@link #release}: CoreHost's picked.*, as
 * still.fail's Android app's PickedFiles.kt).
 */
final class Picks {
    /**
     * An ask: 0 asking, 1 answered, -1 called off or unreadable; what was picked (its info: its id held, 0 for one read
     * whole, its size, its address; "" for a photo taken or a file given by its path).
     */
    static final class Ask {
        volatile int state;
        final List<String> names = new ArrayList<>();
        final List<byte[]> bytes = new ArrayList<>();
        final List<String> infos = new ArrayList<>();
        /** a file bigger than WHOLE may be held (the asker sends it up through the core), else each is read whole */
        boolean hold;
        /** a photo taken now: where the camera writes it whole (the cache's camera/), else only its small preview */
        java.io.File photo;
    }

    /** A file held by its address, too big to be read whole: its size, read a part at a time. */
    static final class Held {
        final Uri uri;
        final long size;

        Held(Uri uri, long size) {
            this.uri = uri;
            this.size = size;
        }
    }

    /** Files read whole up to this; bigger ones held (a Java array of a video's size is more than the heap gives). */
    static final long WHOLE = 16L << 20;
    static final ConcurrentHashMap<Integer, Held> held = new ConcurrentHashMap<>();
    private static int nextHeld = 1;

    static final ConcurrentHashMap<Integer, Ask> asks = new ConcurrentHashMap<>();
    private static int next = 1;
    /** Request codes of the pickers' answers: this and the ask's id. */
    static final int REQUEST = 0x5000;
    private static final long MAX = 1L << 30;

    static synchronized int start(int kind) {
        int id = next++;
        Ask ask = new Ask();
        ask.hold = (kind & 16) != 0;
        int what = kind & 15;
        asks.put(id, ask);
        String given = android.system.Os.getenv("MBUI_PICK_FILES");
        if (given != null && !given.isEmpty()) {
            // scripted runs (as on macOS): every ask answered at once with these files (paths the app can read, as
            // its own files'), no picker
            new Thread(() -> given(id, given.split("\\|")), "mbui-pick").start();
        } else {
            Host.main.post(() -> open(id, what));
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
                    k.infos.add("");
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
                // (no type: photos and videos, as Attach.kt's PickVisualMedia.ImageAndVideo)
                i = new Intent(MediaStore.ACTION_PICK_IMAGES);
                i.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit());
            } else {
                i = documents("*/*");
                i.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {"image/*", "video/*"});
            }
        } else if (kind == 2) {
            i = documents("*/*");
        } else {
            i = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            // the photo whole, written where we give it (without EXTRA_OUTPUT the camera answers a preview of some
            // 200 pixels across)
            Ask k = asks.get(id);
            Uri out = k != null ? photoFile(a, k) : null;
            if (out != null) {
                i.putExtra(MediaStore.EXTRA_OUTPUT, out);
                i.setClipData(ClipData.newRawUri("", out));
                i.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
        }
        try {
            a.startActivityForResult(i, REQUEST + id);
        } catch (ActivityNotFoundException | NullPointerException e) {
            Host.log("pick: no picker for " + i.getAction() + ": " + e);
            done(id, -1);
        }
    }

    /** An empty file of the cache's camera/ for the camera to write a photo into, by its address (Shares.Files). */
    private static Uri photoFile(Activity a, Ask k) {
        try {
            java.io.File dir = new java.io.File(a.getCacheDir(), Shares.CAMERA);
            if (!dir.isDirectory() && !dir.mkdirs()) return null;
            java.io.File f = new java.io.File(dir, "photo-" + System.currentTimeMillis() + ".jpg");
            if (!f.exists() && !f.createNewFile()) return null;
            k.photo = f;
            return new Uri.Builder().scheme("content").authority(a.getPackageName() + ".shared")
                    .appendPath(Shares.CAMERA).appendPath(f.getName()).build();
        } catch (java.io.IOException e) {
            Host.log("pick: " + e);
            return null;
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
        java.io.File taken = k.photo;
        k.photo = null;
        if (result != Activity.RESULT_OK || (data == null && taken == null)) {
            if (taken != null) taken.delete();
            done(id, -1);
            return true;
        }
        ContentResolver cr = Host.activity.getContentResolver();
        new Thread(() -> {
            List<Uri> uris = new ArrayList<>();
            if (taken != null && taken.length() > 0) {
                // the camera wrote the photo whole where we asked (with EXTRA_OUTPUT it answers no data)
                try (InputStream in = new java.io.FileInputStream(taken)) {
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    byte[] buf = new byte[1 << 16];
                    for (int r; (r = in.read(buf)) > 0; ) out.write(buf, 0, r);
                    synchronized (k) {
                        k.names.add(taken.getName());
                        k.bytes.add(out.toByteArray());
                        k.infos.add("");
                    }
                } catch (Exception e) {
                    Host.log("pick: " + taken + ": " + e);
                }
            }
            if (taken != null) taken.delete();
            if (!k.names.isEmpty() || data == null) {
                done(id, k.names.isEmpty() ? -1 : 1);
                return;
            }
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
                    k.infos.add("");
                }
            }
            read(cr, k, uris);
            done(id, k.names.isEmpty() ? -1 : 1);
        }, "mbui-pick").start();
        return true;
    }

    /** Each of `uris` read whole into the ask, or held where it is bigger than WHOLE (one over 1 GB left out). */
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
            if (k.hold && size > WHOLE) {
                int h;
                synchronized (Picks.class) {
                    h = nextHeld++;
                }
                held.put(h, new Held(u, size));
                synchronized (k) {
                    k.names.add(name);
                    k.bytes.add(new byte[0]);
                    k.infos.add(h + "\t" + size + "\t" + u);
                }
                continue;
            }
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
                    // (where it is too: the picture the app's tile draws of it, a video's still: Images.java)
                    k.infos.add("0\t" + out.size() + "\t" + u);
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
        // (the composer's: a video of the gallery goes up through the core a part at a time)
        k.hold = true;
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

    static String info(int id, int i) {
        Ask k = asks.get(id);
        return k == null || i < 0 || i >= k.infos.size() ? "" : k.infos.get(i);
    }

    static void end(int id) {
        asks.remove(id);
    }

    // ── a file held, as the core reads it going up (CoreHost: picked.read, picked.hash, picked.release) ──

    /** Bytes [start, end) of a file held: as many as there are (fewer at its end). */
    static byte[] read(int file, long start, long end) throws java.io.IOException {
        Held h = held.get(file);
        if (h == null) throw new java.io.IOException("no such file picked: " + file);
        int n = (int) Math.max(0, Math.min(end, h.size) - start);
        byte[] out = new byte[n];
        try (android.os.ParcelFileDescriptor fd = Host.activity.getContentResolver().openFileDescriptor(h.uri, "r");
             java.io.FileInputStream in = new java.io.FileInputStream(fd.getFileDescriptor())) {
            java.nio.channels.FileChannel ch = in.getChannel();
            java.nio.ByteBuffer buf = java.nio.ByteBuffer.wrap(out);
            long at = start;
            while (buf.hasRemaining()) {
                int r = ch.read(buf, at);
                if (r <= 0) break;
                at += r;
            }
            return buf.position() == n ? out : java.util.Arrays.copyOf(out, buf.position());
        }
    }

    /** A file held's SHA-256 (lowercase hex), read through once. */
    static String hash(int file) throws Exception {
        Held h = held.get(file);
        if (h == null) throw new java.io.IOException("no such file picked: " + file);
        java.security.MessageDigest d = java.security.MessageDigest.getInstance("SHA-256");
        try (InputStream in = Host.activity.getContentResolver().openInputStream(h.uri)) {
            if (in == null) throw new java.io.IOException("not readable");
            byte[] buf = new byte[1 << 20];
            for (int r; (r = in.read(buf)) > 0; ) d.update(buf, 0, r);
        }
        StringBuilder s = new StringBuilder();
        for (byte b : d.digest()) s.append(String.format("%02x", b & 0xff));
        return s.toString();
    }

    /** A file held let go of (gone up, or taken out of the message). */
    static void release(int file) {
        held.remove(file);
    }
}
