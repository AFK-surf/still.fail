package dev.mbui;

import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Sharing out and in (@hostapi.share, @hostapi.shared_in; still.fail's DriveScreen.kt hand and ShareActivity.kt): words or a
 * file handed to another app through the system's share sheet (a file kept in the cache's shared/ for it, read through
 * Shares.Files, a provider of this app's own that lets another app read only what was handed to it); and what another
 * app shares into this one (ACTION_SEND of text: its words and subject; ACTION_SEND or ACTION_SEND_MULTIPLE of files,
 * read whole), kept for the app to take once.
 */
final class Shares {
    /** What was shared in, as JSON text ({text, title, files: [{name, type, size}]}); taken once (null after). */
    static volatile String sharedIn;
    /** The files of what was shared in, by their place in its `files`, until each is taken. */
    static volatile byte[][] sharedFiles = new byte[0][];
    /** The cache's directory of the pictures put on the clipboard (Device.clipSet), read through Files too. */
    static final String CLIPS = "screen-clips";
    /** The cache's directory of a photo the camera writes whole for the composer (Picks: ACTION_IMAGE_CAPTURE's
     * EXTRA_OUTPUT), written and read through Files: <authority>/camera/<name>. */
    static final String CAMERA = "camera";
    /** A file shared in is read whole, at most this much (the composer takes up to 1 GB). */
    private static final long MAX = 1L << 30;

    /**
     * MainActivity: an ACTION_SEND or ACTION_SEND_MULTIPLE, kept for the app: its words, the subject the app gave with
     * them, its files (EXTRA_STREAM, or the clip the system made of it), each read whole off the main thread first.
     */
    static void take(Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        if (!Intent.ACTION_SEND.equals(action) && !Intent.ACTION_SEND_MULTIPLE.equals(action)) return;
        CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
        String words = text == null ? "" : text.toString().trim();
        String subject = intent.getStringExtra(Intent.EXTRA_SUBJECT);
        List<Uri> uris = streams(intent);
        if (words.isEmpty() && uris.isEmpty()) return;
        if (uris.isEmpty()) {
            keep(words, subject, new JSONArray(), new byte[0][]);
            return;
        }
        ContentResolver cr = Host.activity.getContentResolver();
        new Thread(() -> {
            JSONArray files = new JSONArray();
            List<byte[]> bytes = new ArrayList<>();
            for (Uri u : uris) {
                String name = "file";
                long size = -1;
                try (Cursor c = cr.query(u, new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null)) {
                    if (c != null && c.moveToFirst()) {
                        if (!c.isNull(0)) name = c.getString(0);
                        if (!c.isNull(1)) size = c.getLong(1);
                    }
                } catch (Exception e) {
                    Host.log("shared in: " + e);
                }
                if (size > MAX) {
                    Host.log("shared in: " + name + " is too big (" + size + " bytes)");
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
                    String type = cr.getType(u);
                    files.put(new JSONObject().put("name", name).put("type", type == null ? "" : type).put("size", out.size()));
                    bytes.add(out.toByteArray());
                } catch (Exception e) {
                    Host.log("shared in: " + name + ": " + e);
                }
            }
            if (words.isEmpty() && bytes.isEmpty()) return;
            keep(words, subject, files, bytes.toArray(new byte[0][]));
        }, "mbui-shared-in").start();
    }

    /** The files an intent shares: the clip the system made of its streams, else EXTRA_STREAM itself (one or a list). */
    private static List<Uri> streams(Intent intent) {
        List<Uri> out = new ArrayList<>();
        ClipData clip = intent.getClipData();
        if (clip != null) {
            for (int i = 0; i < clip.getItemCount(); i++) if (clip.getItemAt(i).getUri() != null) out.add(clip.getItemAt(i).getUri());
        }
        if (!out.isEmpty()) return out;
        if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
            List<Uri> list = Build.VERSION.SDK_INT >= 33 ? intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri.class) : legacyList(intent);
            if (list != null) for (Uri u : list) if (u != null) out.add(u);
        } else {
            Uri u = Build.VERSION.SDK_INT >= 33 ? intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri.class) : legacyOne(intent);
            if (u != null) out.add(u);
        }
        return out;
    }

    @SuppressWarnings("deprecation")
    private static List<Uri> legacyList(Intent intent) {
        return intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
    }

    @SuppressWarnings("deprecation")
    private static Uri legacyOne(Intent intent) {
        return intent.getParcelableExtra(Intent.EXTRA_STREAM);
    }

    private static void keep(String words, String subject, JSONArray files, byte[][] bytes) {
        try {
            JSONObject o = new JSONObject().put("text", words);
            if (subject != null && !subject.trim().isEmpty() && !subject.trim().equals(words)) o.put("title", subject.trim());
            if (files.length() > 0) o.put("files", files);
            sharedFiles = bytes;
            sharedIn = o.toString();
            Host.log("shared in: " + words.length() + " characters" + (subject != null ? " (" + subject + ")" : "")
                    + (files.length() > 0 ? ", " + files.length() + " files" : ""));
            Host.requestFrame();
        } catch (JSONException ignored) {
        }
    }

    static String sharedIn() {
        String s = sharedIn;
        sharedIn = null;
        return s;
    }

    /** The i-th file of what was shared in, taken once (empty after, or for none). */
    static byte[] sharedFile(int i) {
        byte[][] all = sharedFiles;
        if (i < 0 || i >= all.length || all[i] == null) return new byte[0];
        byte[] b = all[i];
        all[i] = null;
        return b;
    }

    /** Words, or a file of `data` named `name` (`mime`), handed to the system's share sheet; false when no app takes it. */
    static boolean share(String text, String name, String mime, byte[] data) {
        Context c = Host.activity;
        if (c == null) return false;
        Intent send = new Intent(Intent.ACTION_SEND);
        if (data != null && data.length > 0 && !name.isEmpty()) {
            File dir = new File(c.getCacheDir(), "shared");
            dir.mkdirs();
            File[] old = dir.listFiles();
            if (old != null) for (File f : old) f.delete();
            String safe = name.replace('/', '_').replace('\\', '_');
            File f = new File(dir, safe);
            try (FileOutputStream out = new FileOutputStream(f)) {
                out.write(data);
            } catch (IOException e) {
                Host.log("share: " + e);
                return false;
            }
            Uri uri = new Uri.Builder().scheme("content").authority(c.getPackageName() + ".shared").appendPath(safe).build();
            send.setType(mime.isEmpty() ? "application/octet-stream" : mime).putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            Host.log("share: " + safe + " (" + data.length + " bytes, " + send.getType() + ") to the system's share sheet");
        } else {
            send.setType("text/plain").putExtra(Intent.EXTRA_TEXT, text);
            Host.log("share: " + text.length() + " characters to the system's share sheet");
        }
        Intent chooser = Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        // a scripted run (MBUI_DRIVE_B64) ends its script before the chooser covers the app (its frames stop then)
        boolean scripted = android.system.Os.getenv("MBUI_DRIVE_B64") != null || android.system.Os.getenv("MBUI_DRIVE") != null;
        try {
            Host.main.postDelayed(() -> {
                try {
                    c.startActivity(chooser);
                } catch (ActivityNotFoundException e) {
                    Host.log("share: no app takes it");
                }
            }, scripted ? 1500 : 0);
            return true;
        } catch (ActivityNotFoundException e) {
            return false;
        }
    }

    /** The files handed to another app: read only, only what is in the cache's shared/ (one file at a time), and the
     * pictures put on the clipboard (the cache's screen-clips/); the camera writes a photo taken for the composer into
     * the cache's camera/. */
    public static final class Files extends ContentProvider {
        @Override
        public boolean onCreate() {
            return true;
        }

        private File fileOf(Uri uri) throws FileNotFoundException {
            Context c = getContext();
            String name = uri.getLastPathSegment();
            if (c == null || name == null || name.contains("/") || name.startsWith(".")) throw new FileNotFoundException();
            // a picture put on the clipboard (Device.clipSet): <authority>/screen-clips/<name>
            List<String> path = uri.getPathSegments();
            String dir = path.size() == 2 && (CLIPS.equals(path.get(0)) || CAMERA.equals(path.get(0))) ? path.get(0) : null;
            if (dir == null && path.size() != 1) throw new FileNotFoundException();
            File f = new File(new File(c.getCacheDir(), dir != null ? dir : "shared"), name);
            if (!f.isFile()) throw new FileNotFoundException(name);
            return f;
        }

        @Override
        public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
            if (!"r".equals(mode)) {
                // (only the camera's photo is written, into the empty file Picks made for it)
                List<String> path = uri.getPathSegments();
                if (path.size() != 2 || !CAMERA.equals(path.get(0))) throw new SecurityException("read only");
                return ParcelFileDescriptor.open(fileOf(uri), ParcelFileDescriptor.parseMode(mode));
            }
            return ParcelFileDescriptor.open(fileOf(uri), ParcelFileDescriptor.MODE_READ_ONLY);
        }

        @Override
        public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
            try {
                File f = fileOf(uri);
                MatrixCursor m = new MatrixCursor(new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
                m.addRow(new Object[] {f.getName(), f.length()});
                return m;
            } catch (FileNotFoundException e) {
                return null;
            }
        }

        @Override
        public String getType(Uri uri) {
            String n = uri.getLastPathSegment();
            String ext = n == null || !n.contains(".") ? "" : n.substring(n.lastIndexOf('.') + 1).toLowerCase();
            String t = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
            return t == null ? "application/octet-stream" : t;
        }

        @Override
        public Uri insert(Uri uri, ContentValues values) {
            return null;
        }

        @Override
        public int delete(Uri uri, String selection, String[] args) {
            return 0;
        }

        @Override
        public int update(Uri uri, ContentValues values, String selection, String[] args) {
            return 0;
        }
    }
}
