package dev.mbui;

import android.content.ActivityNotFoundException;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;

/**
 * Sharing out and in (@host.share, @host.shared_in; still.fail's DriveScreen.kt hand and ShareActivity.kt): words or a
 * file handed to another app through the system's share sheet (a file kept in the cache's shared/ for it, read through
 * Shares.Files, a provider of this app's own that lets another app read only what was handed to it); and what another
 * app shares into this one (ACTION_SEND of text: its words and subject), kept for the app to take once.
 */
final class Shares {
    /** What was shared in, as JSON text ({text, title}); taken once (null after). */
    static volatile String sharedIn;

    /** MainActivity: an ACTION_SEND of text, kept for the app (its words, the subject the app gave with them). */
    static void take(Intent intent) {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) return;
        CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
        String words = text == null ? "" : text.toString().trim();
        if (words.isEmpty()) return;
        String subject = intent.getStringExtra(Intent.EXTRA_SUBJECT);
        try {
            org.json.JSONObject o = new org.json.JSONObject().put("text", words);
            if (subject != null && !subject.trim().isEmpty() && !subject.trim().equals(words)) o.put("title", subject.trim());
            sharedIn = o.toString();
            Host.log("shared in: " + words.length() + " characters" + (subject != null ? " (" + subject + ")" : ""));
            Host.requestFrame();
        } catch (org.json.JSONException ignored) {
        }
    }

    static String sharedIn() {
        String s = sharedIn;
        sharedIn = null;
        return s;
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

    /** The files handed to another app: read only, only what is in the cache's shared/ (one file at a time). */
    public static final class Files extends ContentProvider {
        @Override
        public boolean onCreate() {
            return true;
        }

        private File fileOf(Uri uri) throws FileNotFoundException {
            Context c = getContext();
            String name = uri.getLastPathSegment();
            if (c == null || name == null || name.contains("/") || name.startsWith(".")) throw new FileNotFoundException();
            File f = new File(new File(c.getCacheDir(), "shared"), name);
            if (!f.isFile()) throw new FileNotFoundException(name);
            return f;
        }

        @Override
        public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
            if (!"r".equals(mode)) throw new SecurityException("read only");
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
