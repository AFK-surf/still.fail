package dev.mbui;

import android.opengl.EGL14;
import android.opengl.EGLDisplay;

/**
 * What the drawing thread would otherwise do for the first time inside the app's first frames, done as the app starts,
 * on a thread of its own, while the system makes the activity and lays its window out: the GPU's driver loaded and its
 * display set up (EGL: GLSurfaceView's own then finds it so; the driver's libraries and their symbols loaded), and
 * whether there is an H.264 decoder here (Streams.h264Here: the system's codecs listed, asked as a page that may show
 * a screen is built). Once a run.
 */
final class WarmUp {
    private static boolean started;

    static void start() {
        if (started) return;
        started = true;
        Thread t = new Thread(() -> {
            EGLDisplay d = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
            int[] version = new int[2];
            if (d != EGL14.EGL_NO_DISPLAY) EGL14.eglInitialize(d, version, 0, version, 1);
            Streams.h264Here();
        }, "mbui-warm-up");
        t.start();
    }
}
