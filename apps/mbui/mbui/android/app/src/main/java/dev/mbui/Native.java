package dev.mbui;

/** libmbui.so: the MoonBit app, its runtime and the C side of the host. */
final class Native {
    static {
        System.loadLibrary("mbui");
    }

    static native void start();
    static native void surfaceCreated();
    static native void resize(int w, int h);
    /** A frame at `now`, the one before it `late` ms late to the screen (@hostapi.frame_late). */
    static native boolean frame(float w, float h, float scale, double now, double late);
    /** The last frame drawn again as it was presented, the native views' pictures as they are now (android_host.c). */
    static native void redraw();
    static native void pointer(int kind, float x, float y, double time);
    /** A touch screen's finger (kind 10 down, 11 moved, 12 up, 13 called off), by its pointer id, at its own time. */
    static native void touch(int kind, int id, float x, float y, double time);
    static native void key(int code, int mods);
    static native void text(int kind, String s, int a, int b);
    static native void back(int kind, float x, float progress, int edge);
    static native void appState(int state);
    /** Over another app (OverActivity) or not: what the app does not paint is left clear (android_host.c present). */
    static native void overOther(boolean on);
    /** A message for the app's next frame on `channel` (post.h's mb_post: any thread): its JSON's UTF-8. */
    static native void postBytes(String channel, byte[] json);

    /** `json` posted as UTF-8 (Java's own encoding of a String into JNI is modified UTF-8, which an emoji is not). */
    static void post(String channel, String json) {
        postBytes(channel, json.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
    static native int atlasTexture();

    static native int colourAtlasTexture();
    static native boolean snapshot(String path);
    static native void imageDone(int id, int tex, int w, int h, int ow, int oh);
    /** What the host did for the app is done (android_host.c's mb_host_set_outside): on the GL thread. */
    static native void outside(int kind, int id, int state);

    // The kinds of what the host does for the app (src/ui/hostcall.mbt's outside_*, named as there).
    static final int OUTSIDE_IMAGE = 1, OUTSIDE_VIEW = 2, OUTSIDE_PICK = 3, OUTSIDE_GALLERY = 4, OUTSIDE_MARKS = 5,
            OUTSIDE_GRAB = 6, OUTSIDE_UPDATE = 7, OUTSIDE_CLIP = 9, OUTSIDE_NATIVE = 10, OUTSIDE_POSTED = 11,
            OUTSIDE_STREAMED = 12, OUTSIDE_STOOD = 13;

    /** Something posted since (Host.posted, on the GL thread): the app told, or a frame asked for (android_host.c). */
    static native void posted();

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
