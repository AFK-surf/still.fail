package dev.mbui;

import android.Manifest;
import android.app.Activity;
import android.content.ContentUris;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.provider.Settings;

import java.util.concurrent.ConcurrentHashMap;

/**
 * The phone's gallery for a picker's recent photos and videos (src/hostapi/gallery.mbt; still.fail's Android app,
 * chat/screens/Attach.kt photoAccess, AttachLaunchers.askPhotos, recentPhotos): how much of it the app may read, asking
 * for it (asked and turned down for good, the app's page of the system's settings), and its photos and videos with
 * their times, read off the main thread (the view ranks them: Attach.kt latest). One is drawn by its content://
 * address (Images.java: the gallery's thumbnail, a video's still) and read by Picks.photo (held, where it is big).
 */
final class Gallery {
    /** The request code of the permissions' answer (MainActivity.onRequestPermissionsResult). */
    static final int ASK = 0x7100;
    private static final String ASKED = "attach.gallery.asked";
    static volatile int answers;

    private static boolean has(Context c, String p) {
        return c.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * 1 all of it (photos and videos), 2 some (the ones chosen for the app on Android 14 on, or the photos alone: a
     * phone that allowed them before videos were asked for), 0 none (Attach.kt photoAccess).
     */
    static int access() {
        Activity a = Host.activity;
        if (a == null) return 0;
        if (Build.VERSION.SDK_INT < 33) return has(a, Manifest.permission.READ_EXTERNAL_STORAGE) ? 1 : 0;
        boolean photos = has(a, Manifest.permission.READ_MEDIA_IMAGES);
        boolean videos = has(a, Manifest.permission.READ_MEDIA_VIDEO);
        if (photos && videos) return 1;
        if (photos || videos) return 2;
        if (Build.VERSION.SDK_INT >= 34 && has(a, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)) return 2;
        return 0;
    }

    private static String[] asked() {
        if (Build.VERSION.SDK_INT >= 34) return new String[] {
            Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED};
        if (Build.VERSION.SDK_INT >= 33) return new String[] {Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO};
        return new String[] {Manifest.permission.READ_EXTERNAL_STORAGE};
    }

    /** The system's dialog; asked before and turned down for good (it shows none any more), the app's settings. */
    static void ask() {
        Activity a = Host.activity;
        if (a == null) return;
        Host.main.post(() -> {
            SharedPreferences prefs = a.getSharedPreferences("mbui", Context.MODE_PRIVATE);
            boolean refused = prefs.getBoolean(ASKED, false) && access() == 0;
            if (refused) for (String p : asked()) if (a.shouldShowRequestPermissionRationale(p)) refused = false;
            if (refused) {
                Host.log("gallery: refused for good, the app's settings");
                a.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", a.getPackageName(), null)));
            } else {
                prefs.edit().putBoolean(ASKED, true).apply();
                a.requestPermissions(asked(), ASK);
            }
        });
    }

    /** MainActivity: the system answered (whatever it said: the view reads the gallery again). */
    static void answered() {
        answers++;
        Host.log("gallery: answered, access " + access());
        Host.requestFrame();
    }

    static int answers() {
        return answers;
    }

    /** A read: 0 reading, 1 read, -1 failed; its rows (id, src, added, modified, taken, video: a tab between, a line each). */
    static final class Read {
        volatile int state;
        volatile String rows = "";
    }

    static final ConcurrentHashMap<Integer, Read> reads = new ConcurrentHashMap<>();
    private static int next = 1;

    static synchronized int read() {
        Activity a = Host.activity;
        if (a == null) return 0;
        int id = next++;
        Read r = new Read();
        reads.put(id, r);
        new Thread(() -> {
            // photos and videos (Attach.kt recentPhotos: MediaStore.Files, its media type), each by its own collection's
            // address (Images' or Video's: what the thumbnail and the read take)
            Uri from = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL);
            String type = MediaStore.Files.FileColumns.MEDIA_TYPE;
            String[] cols = {MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DATE_ADDED,
                    MediaStore.Files.FileColumns.DATE_MODIFIED, MediaStore.Files.FileColumns.DATE_TAKEN, type};
            String visual = type + " IN (" + MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE + ", " + MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO + ")";
            StringBuilder out = new StringBuilder();
            try (Cursor c = a.getContentResolver().query(from, cols, visual, null, null)) {
                while (c != null && c.moveToNext()) {
                    long id_ = c.getLong(0);
                    boolean video = c.getInt(4) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO;
                    Uri collection = video ? MediaStore.Video.Media.EXTERNAL_CONTENT_URI : MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                    out.append(id_).append('\t').append(ContentUris.withAppendedId(collection, id_)).append('\t')
                            .append(c.isNull(1) ? -1 : c.getLong(1)).append('\t')
                            .append(c.isNull(2) ? -1 : c.getLong(2)).append('\t')
                            // taken is in milliseconds: in seconds as the others
                            .append(c.isNull(3) ? -1 : c.getLong(3) / 1000).append('\t')
                            .append(video ? 1 : 0).append('\n');
                }
                r.rows = out.toString();
                r.state = 1;
            } catch (Exception e) {
                Host.log("gallery: " + e);
                r.state = -1;
            }
            Native.tell(Native.OUTSIDE_GALLERY, id, r.state);
        }, "mbui-gallery").start();
        return id;
    }

    static int readState(int id) {
        Read r = reads.get(id);
        return r == null ? -1 : r.state;
    }

    static String readRows(int id) {
        Read r = reads.get(id);
        return r == null ? "" : r.rows;
    }

    static void readEnd(int id) {
        reads.remove(id);
    }
}
