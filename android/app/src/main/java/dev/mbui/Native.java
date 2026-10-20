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
    /** A run to a declared moment (MBView: Host.shotAt): the app's clock is its frames' (mb_host_now). */
    static native void ownClock();
    /** How many of the app's asks of the host are not answered yet, as its last frame said (mb_host_frame_awaiting). */
    static native int awaiting();
}
