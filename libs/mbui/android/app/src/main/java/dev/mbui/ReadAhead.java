package dev.mbui;

import android.content.Context;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;

/**
 * This build's files (its APK, the libraries taken out of it, its dex as ART made it) read into memory as the app
 * starts, behind it. Android reads an app's code and what it carries from storage only as each page of it is first
 * used, and an install leaves none of them in memory: the first run of a build had its drawing thread stop on each
 * page it came to first (2026-10-24, the emulator scrolling Home: 2 000 reads from storage on the drawing thread
 * after an install, none once the app was launched again; on a phone each is a wait on its flash, and a page first
 * shown has many of them in a frame: every update was slow for a while, launching again was not). Each is mapped and loaded
 * here (MappedByteBuffer.load: the system told it is all wanted, madvise WILLNEED, then a byte of each page read), on a
 * thread of its own, apart from the drawing; what is in memory already, as when the app is launched again, is not read
 * from storage again.
 */
final class ReadAhead {
    private static boolean started;

    /** Once a run (the activity made again does not ask again). */
    static void start(Context c) {
        if (started) return;
        started = true;
        File dir = new File(c.getApplicationInfo().sourceDir).getParentFile();
        if (dir == null) return;
        Thread t = new Thread(() -> under(dir), "mbui-read-ahead");
        // (the least: what the drawing thread waits for comes first)
        t.setPriority(Thread.MIN_PRIORITY);
        t.start();
    }

    private static void under(File dir) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) under(f);
            else wanted(f);
        }
    }

    private static void wanted(File f) {
        try (FileInputStream in = new FileInputStream(f); FileChannel ch = in.getChannel()) {
            long n = ch.size();
            if (n > 0) ch.map(FileChannel.MapMode.READ_ONLY, 0, n).load();
        } catch (IOException | RuntimeException e) {
            Host.log("read ahead: " + f.getName() + ": " + e);
        }
    }
}
