package dev.mbui;

import android.os.Handler;
import android.os.Looper;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 共享调试's own way to the core (AdbShare.java): its service asks the core and follows the `adbShare` topic while the
 * app is behind, when the app's frames (and so its MoonBit client) have stopped. On the UI's own client
 * (src/host/android_core.c java_send), with ids of its own from 1e9 on, which the app's client never reaches; what the
 * core says to them comes back to {@link #says} instead of the app. Its answers and values on the main thread.
 */
final class AdbCore {
    private AdbCore() {}

    /** To the core (android_core.c registers it once the core's classes are found); nothing before the core runs. */
    static native void send(String json);

    /** A call's answer: its `ok`, or the core's error's message. */
    interface Answer {
        void ok(Object value);

        void error(String why);
    }

    /** A topic's whole value as it changes (its deltas applied), or its error. */
    interface Follow {
        void value(Object value);
    }

    private static final AtomicLong next = new AtomicLong(1_000_000_000L);
    private static final ConcurrentHashMap<Long, Answer> calls = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Long, Topic> topics = new ConcurrentHashMap<>();
    private static final Handler main = new Handler(Looper.getMainLooper());

    private static final class Topic {
        final Follow follow;
        Object value;

        Topic(Follow follow) {
            this.follow = follow;
        }
    }

    /** `name` asked with `params`; `answer` told on the main thread. */
    static void call(String name, JSONObject params, Answer answer) {
        long id = next.getAndIncrement();
        if (answer != null) calls.put(id, answer);
        try {
            JSONObject m = new JSONObject();
            m.put("id", id);
            m.put("call", name);
            m.put("params", params == null ? new JSONObject() : params);
            send(m.toString());
        } catch (Throwable e) {
            calls.remove(id);
            if (answer != null) main.post(() -> answer.error(String.valueOf(e)));
        }
    }

    /** `topic` followed until `unfollow` with the id this gives. */
    static long follow(String topic, Follow follow) {
        long id = next.getAndIncrement();
        topics.put(id, new Topic(follow));
        try {
            JSONObject m = new JSONObject();
            m.put("id", id);
            m.put("subscribe", new JSONObject().put("topic", topic));
            send(m.toString());
        } catch (Throwable e) {
            topics.remove(id);
            Host.log("adb core: " + e);
        }
        return id;
    }

    static void unfollow(long id) {
        if (topics.remove(id) == null) return;
        try {
            send(new JSONObject().put("id", id).put("unsubscribe", true).toString());
        } catch (Throwable e) {
            Host.log("adb core: " + e);
        }
    }

    /** What the core said to one of these ids (android_core.c, the core's thread). */
    static void says(byte[] json) {
        final JSONObject m;
        try {
            m = new JSONObject(new String(json, StandardCharsets.UTF_8));
        } catch (Exception e) {
            Host.log("adb core: an unreadable message: " + e);
            return;
        }
        long id = m.optLong("id", -1);
        main.post(() -> take(id, m));
    }

    private static void take(long id, JSONObject m) {
        Answer a = calls.get(id);
        if (a != null) {
            calls.remove(id);
            if (m.has("error")) a.error(why(m.opt("error")));
            else a.ok(m.opt("ok"));
            return;
        }
        Topic t = topics.get(id);
        if (t == null) return;
        if (m.has("value")) {
            t.value = m.opt("value");
        } else if (m.has("delta")) {
            JSONArray ops = m.optJSONArray("delta");
            if (ops != null) for (int i = 0; i < ops.length(); i++) t.value = apply(t.value, ops.optJSONObject(i));
        } else if (m.has("error")) {
            t.value = null;
        } else {
            return;
        }
        t.follow.value(t.value);
    }

    private static String why(Object error) {
        if (error instanceof JSONObject) {
            String s = ((JSONObject) error).optString("message", "");
            if (!s.isEmpty()) return s;
        }
        return String.valueOf(error);
    }

    /** One of the core's delta ops (client/core-ts delta.ts: set, append, remove at a path) applied to `value`. */
    static Object apply(Object value, JSONObject op) {
        if (op == null) return value;
        JSONArray path = op.optJSONArray("path");
        int n = path == null ? 0 : path.length();
        if (n == 0) {
            if (op.has("set")) return op.opt("set");
            if (op.has("append") && value instanceof JSONArray) {
                JSONArray more = op.optJSONArray("append");
                for (int i = 0; more != null && i < more.length(); i++) ((JSONArray) value).put(more.opt(i));
            }
            return op.has("remove") ? null : value;
        }
        // down to the parent of the path's last step
        Object at = value;
        for (int i = 0; i < n - 1; i++) at = step(at, path.opt(i));
        Object last = path.opt(n - 1);
        try {
            if (op.has("set")) {
                if (at instanceof JSONObject) ((JSONObject) at).put(String.valueOf(last), op.opt("set"));
                else if (at instanceof JSONArray) ((JSONArray) at).put(((Number) last).intValue(), op.opt("set"));
            } else if (op.has("append")) {
                Object arr = step(at, last);
                JSONArray more = op.optJSONArray("append");
                if (arr instanceof JSONArray) for (int i = 0; more != null && i < more.length(); i++) ((JSONArray) arr).put(more.opt(i));
            } else if (op.has("remove")) {
                if (at instanceof JSONObject) ((JSONObject) at).remove(String.valueOf(last));
                else if (at instanceof JSONArray) ((JSONArray) at).remove(((Number) last).intValue());
            }
        } catch (Exception e) {
            Host.log("adb core: a delta not applied: " + e);
        }
        return value;
    }

    private static Object step(Object at, Object key) {
        if (at instanceof JSONObject) return ((JSONObject) at).opt(String.valueOf(key));
        if (at instanceof JSONArray && key instanceof Number) return ((JSONArray) at).opt(((Number) key).intValue());
        return null;
    }
}
