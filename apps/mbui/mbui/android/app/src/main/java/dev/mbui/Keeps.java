package dev.mbui;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Files the app has read kept on the phone (src/hostapi/keep.mbt): its bytes put a part at a time into a file of the
 * cache (keeping/), then, once all there, copied into Downloads through MediaStore, nothing asked, as still.fail's
 * Android app's download() does (FileKinds.kt: a file of its DriveCache copied there); or where the person chooses,
 * the documents UI's ACTION_CREATE_DOCUMENT. Copied off the main thread; MoonBit asks after each keep every frame
 * (android_host.c).
 */
final class Keeps {
    /** A keep: 0 keeping, 1 kept, 2 called off, -1 failed; where it went; its part file while it comes. */
    static final class Keep {
        volatile int state;
        volatile String where = "";
        final String name, mime;
        final int way;
        final File part;
        FileOutputStream out;
        long size;

        Keep(String name, String mime, int way, File part) {
            this.name = name;
            this.mime = mime;
            this.way = way;
            this.part = part;
        }
    }

    static final ConcurrentHashMap<Integer, Keep> keeps = new ConcurrentHashMap<>();
    private static int next = 1;
    /** Request codes of the documents UI's answers: this and the keep's id. */
    static final int REQUEST = 0x6000;

    static synchronized int begin(String name, String mime, int way) {
        Activity a = Host.activity;
        if (a == null) return 0;
        int id = next++;
        String safe = name.replace('/', '_').replace('\\', '_').trim();
        if (safe.isEmpty() || safe.equals(".") || safe.equals("..")) safe = "file";
        File dir = new File(a.getCacheDir(), "keeping/" + id);
        dir.mkdirs();
        Keep k = new Keep(safe, mime == null || mime.isEmpty() ? "application/octet-stream" : mime, way, new File(dir, safe));
        try {
            k.out = new FileOutputStream(k.part);
        } catch (IOException e) {
            Host.log("keep " + safe + ": " + e);
            k.state = -1;
        }
        keeps.put(id, k);
        return id;
    }

    static int append(int id, byte[] data) {
        Keep k = keeps.get(id);
        if (k == null || k.out == null || k.state != 0) return 0;
        try {
            k.out.write(data);
            k.size += data.length;
            return 1;
        } catch (IOException e) {
            Host.log("keep " + k.name + ": " + e);
            close(k);
            done(k, -1, "");
            return 0;
        }
    }

    static void finish(int id) {
        Keep k = keeps.get(id);
        if (k == null || k.out == null || k.state != 0) return;
        close(k);
        if (k.way == 2) {
            Host.main.post(() -> choose(id, k));
        } else {
            new Thread(() -> downloads(k), "mbui-keep").start();
        }
    }

    private static void close(Keep k) {
        try {
            if (k.out != null) k.out.close();
        } catch (IOException ignored) {
        }
        k.out = null;
    }

    /** Into Downloads (MediaStore.Downloads, API 29+: no permission asked), pending until whole; the name as MediaStore made it. */
    private static void downloads(Keep k) {
        ContentResolver cr = Host.activity.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, k.name);
        if (!k.mime.equals("application/octet-stream")) values.put(MediaStore.Downloads.MIME_TYPE, k.mime);
        values.put(MediaStore.Downloads.IS_PENDING, 1);
        Uri uri = null;
        try {
            uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IOException("MediaStore made no entry");
            copy(cr, uri, k);
            ContentValues whole = new ContentValues();
            whole.put(MediaStore.Downloads.IS_PENDING, 0);
            cr.update(uri, whole, null, null);
            String shown = nameOf(cr, uri, k.name);
            Host.log("keep: " + shown + " (" + k.size + " bytes) in Downloads");
            done(k, 1, "Download/" + shown);
        } catch (Exception e) {
            Host.log("keep " + k.name + ": " + e);
            if (uri != null) try { cr.delete(uri, null, null); } catch (Exception ignored) { }
            done(k, -1, "");
        }
    }

    /** The documents UI asks where (named as the file is), then the file is copied there. */
    private static void choose(int id, Keep k) {
        Activity a = Host.activity;
        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(k.mime)
                .putExtra(Intent.EXTRA_TITLE, k.name);
        try {
            a.startActivityForResult(i, REQUEST + id);
        } catch (ActivityNotFoundException | NullPointerException e) {
            Host.log("keep: no documents UI: " + e);
            done(k, -1, "");
        }
    }

    /** MainActivity.onActivityResult: the documents UI answered. */
    static boolean answered(int request, int result, Intent data) {
        int id = request - REQUEST;
        Keep k = keeps.get(id);
        if (k == null || request < REQUEST || request >= REQUEST + 0x1000) return false;
        if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
            done(k, 2, "");
            return true;
        }
        Uri uri = data.getData();
        ContentResolver cr = Host.activity.getContentResolver();
        new Thread(() -> {
            try {
                copy(cr, uri, k);
                String shown = nameOf(cr, uri, k.name);
                Host.log("keep: " + shown + " (" + k.size + " bytes) where chosen");
                done(k, 1, shown);
            } catch (Exception e) {
                Host.log("keep " + k.name + ": " + e);
                done(k, -1, "");
            }
        }, "mbui-keep").start();
        return true;
    }

    private static void copy(ContentResolver cr, Uri uri, Keep k) throws IOException {
        try (OutputStream out = cr.openOutputStream(uri, "w"); InputStream in = new FileInputStream(k.part)) {
            if (out == null) throw new IOException("no stream for " + uri);
            byte[] buf = new byte[1 << 16];
            for (int r; (r = in.read(buf)) > 0; ) out.write(buf, 0, r);
        }
    }

    private static String nameOf(ContentResolver cr, Uri uri, String fallback) {
        try (Cursor c = cr.query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst() && !c.isNull(0)) return c.getString(0);
        } catch (Exception ignored) {
        }
        return fallback;
    }

    private static void drop(Keep k) {
        k.part.delete();
        File dir = k.part.getParentFile();
        if (dir != null) dir.delete();
    }

    private static void done(Keep k, int state, String where) {
        drop(k);
        k.where = where;
        k.state = state;
        Host.requestFrame();
    }

    static int state(int id) {
        Keep k = keeps.get(id);
        return k == null ? -1 : k.state;
    }

    static String where(int id) {
        Keep k = keeps.get(id);
        return k == null ? "" : k.where;
    }

    /**
     * Bytes {@code start} to {@code end} of a file kept in Downloads, read back ({@code where} as a keep said it:
     * "Download/" and its name as MediaStore made it, an entry of this app's): null when it is no longer there, or it
     * was kept where the person chose (theirs, named only). The still.fail client core's downloads read a chat's file
     * saved here from here (CoreHost's kept.read).
     */
    static byte[] read(String where, long start, long end) {
        String in = Environment.DIRECTORY_DOWNLOADS + "/";
        MainActivity a = Host.activity;
        if (a == null || !where.startsWith(in) || end < start) return null;
        ContentResolver cr = a.getContentResolver();
        String[] id = {MediaStore.Downloads._ID};
        String which = MediaStore.Downloads.DISPLAY_NAME + " = ? AND " + MediaStore.Downloads.RELATIVE_PATH + " = ?";
        try (Cursor c = cr.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id, which, new String[] {where.substring(in.length()), in}, null)) {
            if (c == null || !c.moveToFirst()) return null;
            Uri uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, c.getLong(0));
            try (InputStream s = cr.openInputStream(uri)) {
                if (s == null) return null;
                for (long skipped = 0; skipped < start;) {
                    long n = s.skip(start - skipped);
                    if (n <= 0) return null;
                    skipped += n;
                }
                byte[] out = new byte[(int) (end - start)];
                int got = 0;
                while (got < out.length) {
                    int n = s.read(out, got, out.length - got);
                    if (n < 0) break;
                    got += n;
                }
                return got == out.length ? out : Arrays.copyOf(out, got);
            }
        } catch (Exception e) {
            Host.log("keep: " + where + " not read back: " + e);
            return null;
        }
    }

    /** Let go of; one still coming is called off, its part file removed (one being copied finishes on its own). */
    static void end(int id) {
        Keep k = keeps.remove(id);
        if (k != null && k.out != null) {
            close(k);
            drop(k);
        }
    }
}
