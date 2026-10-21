package dev.mbui;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * An app's own calls of its host (src/host/native.mbt, @ui.native_call): what the app's own code puts here for a name
 * (still.fail's AdbShare: "adb.phone", "adb.open", …) answers that name's calls. A handler is given the call's params
 * (JSON) and its Reply, and answers once, on any thread, now or later; the answer reaches the app as an outside of kind
 * OUTSIDE_NATIVE at a frame's boundary. A name nobody put here is answered at once that it cannot be.
 */
public final class Natives {
    private Natives() {}

    /** A call's answer, given once: its JSON (`ok`) or why not (`fail`). */
    public interface Reply {
        void ok(String json);

        void fail(String why);
    }

    /** Answers a call of its name: `params` its JSON (an object), on the GL thread; it may answer later, elsewhere. */
    public interface Handler {
        void call(String params, Reply reply);
    }

    private static final ConcurrentHashMap<String, Handler> handlers = new ConcurrentHashMap<>();

    /** `handler` answers the calls named `name` from now on (the last put for a name). */
    public static void put(String name, Handler handler) {
        handlers.put(name, handler);
    }

    /** A call: 0 asking, 1 answered, -1 refused; its answer's JSON or why not. */
    private static final class Call {
        volatile int state;
        volatile String said = "";
    }

    private static final ConcurrentHashMap<Integer, Call> calls = new ConcurrentHashMap<>();
    private static final AtomicInteger next = new AtomicInteger(1);

    /** `name` asked with `params` (android_device.h, the GL thread): its id. */
    static int call(String name, String params) {
        int id = next.getAndIncrement();
        Call c = new Call();
        calls.put(id, c);
        Handler h = handlers.get(name);
        Reply reply = new Reply() {
            private boolean said;

            private synchronized boolean once() {
                if (said) return false;
                said = true;
                return true;
            }

            @Override
            public void ok(String json) {
                if (!once()) return;
                c.said = json == null ? "null" : json;
                c.state = 1;
                Native.tell(Native.OUTSIDE_NATIVE, id, 1);
            }

            @Override
            public void fail(String why) {
                if (!once()) return;
                c.said = why == null ? "" : why;
                c.state = -1;
                Native.tell(Native.OUTSIDE_NATIVE, id, -1);
            }
        };
        if (h == null) {
            reply.fail("no native call " + name + " in this app");
            return id;
        }
        try {
            h.call(params, reply);
        } catch (Exception e) {
            Host.log("native " + name + ": " + e);
            reply.fail(String.valueOf(e));
        }
        return id;
    }

    static int state(int id) {
        Call c = calls.get(id);
        return c == null ? -1 : c.state;
    }

    static String result(int id) {
        Call c = calls.get(id);
        return c == null ? "" : c.said;
    }

    static void end(int id) {
        calls.remove(id);
    }
}
