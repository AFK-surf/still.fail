package dev.mbui;

/** libmbui.so: the MoonBit app, its runtime and the C side of the host. */
final class Native {
    static {
        System.loadLibrary("mbui");
    }

    static native void start();
    static native void surfaceCreated();
    static native void resize(int w, int h);
    static native boolean frame(float w, float h, float scale, double now);
    static native void pointer(int kind, float x, float y, double time);
    static native void key(int code, int mods);
    static native void text(int kind, String s, int a, int b);
    static native void back(int kind, float x, float progress, int edge);
    static native void appState(int state);
    static native int atlasTexture();
    static native boolean snapshot(String path);
    static native void imageDone(int id, int tex, int w, int h, int ow, int oh);
    /** What the host did for the app is done (android_host.c's mb_host_set_outside): on the GL thread. */
    static native void outside(int kind, int id, int state);

    // The kinds of what the host does for the app (src/ui/hostcall.mbt's outside_*, named as there).
    static final int OUTSIDE_IMAGE = 1, OUTSIDE_VIEW = 2, OUTSIDE_PICK = 3, OUTSIDE_GALLERY = 4, OUTSIDE_MARKS = 5,
            OUTSIDE_GRAB = 6, OUTSIDE_UPDATE = 7;

    /** `outside` told on the GL thread, between frames, from any thread here (and a frame asked for). */
    static void tell(int kind, int id, int state) {
        MBView v = Host.view;
        if (v != null) v.toGL(() -> outside(kind, id, state));
        Host.requestFrame();
    }
    /** A run to a declared moment (MBView: Host.shotAt): the app's clock is its frames' (mb_host_now). */
    static native void ownClock();
    /** How many of the app's asks of the host are not answered yet, as its last frame said (mb_host_frame_awaiting). */
    static native int awaiting();
}
