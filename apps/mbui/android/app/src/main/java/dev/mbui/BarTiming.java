package dev.mbui;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.ActionMode;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.KeyboardShortcutGroup;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.SearchEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * How long a switch between places on the bottom bar takes, and where the time goes, as still.fail's Android app times
 * it (BarTiming.kt; docs/telemetry.md → 安卓 {@code bar_switch}): from the finger lifted to the place's page on the
 * stack (src/sfapp go_place, told by src/stillfail/reports.mbt), to the end of the first frame's build that had it and
 * the frame after (handed to the display); and for each topic the page subscribed anew, how long the core took to give
 * its first value (taken and decoded on the UI's thread) and how big it was. Logged on the device ({@code adb logcat -s
 * StillfailTiming}), and to PostHog as the account signed in, in a build with its key, unless turned off (Crashes).
 * Only names of places and topics, counts and times: nothing a person wrote, no ids.
 *
 * Told from the UI's (GL) thread; the frames counted are the main thread's (Choreographer), as the Android app's.
 */
final class BarTiming {
    private BarTiming() {}

    private static final String TAG = "StillfailTiming";
    /** A switch is told once its page is drawn and each topic it followed anew has a value; at the latest this long after. */
    private static final long LONGEST_MS = 3_000L;
    /** A finger lifted longer ago than this is not what switched (the back gesture). */
    private static final long TAP_MS = 1_000L;
    /** Sent to PostHog in batches: once this many are waiting, or this long after the first. */
    private static final int BATCH = 20;
    private static final long BATCH_MS = 60_000L;

    private static volatile Context context;
    private static volatile long lastUp;
    private static final Handler main = new Handler(Looper.getMainLooper());
    private static final Object lock = new Object();
    /** The places shown since the app started, and when each was last left (ns). */
    private static final HashSet<String> seen = new HashSet<>();
    private static final HashMap<String, Long> left = new HashMap<>();
    /** The switch being timed; a new one tells it as it stands. */
    private static Switch on;
    private static final List<JSONObject> waiting = new ArrayList<>();

    private static final class Topic {
        final String name;
        final long at;
        long arrived;
        int bytes = -1;
        boolean failed;

        Topic(String name, long at) {
            this.name = name;
            this.at = at;
        }
    }

    private static final class Switch {
        final String from, to;
        final long tap, placed;
        final boolean touched, first;
        final Long awayMs;
        long built, frame;
        boolean done;
        final LinkedHashMap<Integer, Topic> topics = new LinkedHashMap<>();
        /** The frames' times (ns, Choreographer's) from the tap until it is told: how the main thread kept up. */
        final List<Long> frames = new ArrayList<>();
        final Choreographer.FrameCallback ticking = new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long at) {
                synchronized (lock) {
                    if (done || frames.size() >= 200) return;
                    frames.add(at);
                }
                Choreographer.getInstance().postFrameCallback(this);
            }
        };

        Switch(String from, String to, long tap, boolean touched, long placed, boolean first, Long awayMs) {
            this.from = from;
            this.to = to;
            this.tap = tap;
            this.touched = touched;
            this.placed = placed;
            this.first = first;
            this.awayMs = awayMs;
        }
    }

    /** Every touch of the activity, through its window's callback (mbui's MainActivity is the host's): the last
     *  finger lifted is where a switch from the bar begins. */
    static void start(Application app) {
        context = app;
        app.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity a, Bundle saved) {
                Window w = a.getWindow();
                Window.Callback c = w.getCallback();
                if (c != null && !(c instanceof Touches)) w.setCallback(new Touches(c));
            }

            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityResumed(Activity a) {}
            @Override public void onActivityPaused(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle out) {}
            @Override public void onActivityDestroyed(Activity a) {}
        });
    }

    static void touched(MotionEvent e) {
        if (e.getActionMasked() == MotionEvent.ACTION_UP) lastUp = e.getEventTime() * 1_000_000L;
    }

    /** A place's page put on the stack in place of {@code from}'s ("" none), at {@code now} (ns). */
    static void placed(String from, String to, long now) {
        Switch s;
        synchronized (lock) {
            if (on != null) finish(on, true);
            String was = from.isEmpty() ? null : from;
            if (was != null) {
                left.put(was, now);
                seen.add(was);
            }
            long up = lastUp;
            boolean touched = up != 0L && now - up >= 0 && now - up <= TAP_MS * 1_000_000L;
            Long since = left.get(to);
            s = new Switch(was, to, touched ? up : now, touched, now, seen.add(to), since != null ? (now - since) / 1_000_000L : null);
            on = s;
        }
        main.post(() -> Choreographer.getInstance().postFrameCallback(s.ticking));
        main.postDelayed(() -> {
            synchronized (lock) {
                finish(s, false);
            }
        }, LONGEST_MS);
    }

    /** The first frame's build that had the page {@code place} is over, at {@code now}: the frame after it is the one
     *  that put it on the display. */
    static void built(String place, long now) {
        Switch s;
        synchronized (lock) {
            s = on;
            if (s == null || !s.to.equals(place) || s.built != 0L) return;
            s.built = now;
        }
        main.post(() -> Choreographer.getInstance().postFrameCallback(t -> {
            synchronized (lock) {
                s.frame = System.nanoTime();
                settle(s);
            }
        }));
    }

    /** A topic subscribed anew (its subscription's id, its name) at {@code now}: whether it is timed (a switch is). */
    static boolean followed(int id, String name, long now) {
        synchronized (lock) {
            Switch s = on;
            if (s == null || s.done || (s.built != 0L && now - s.built > 500_000_000L)) return false;
            if (s.topics.containsKey(id)) return false;
            s.topics.put(id, new Topic(name, now));
            return true;
        }
    }

    /** Its first message taken (decoded) at {@code now}: its value's size in bytes, or -1 (it could not be read). */
    static void decoded(int id, int bytes, long now) {
        synchronized (lock) {
            Switch s = on;
            if (s == null) return;
            Topic t = s.topics.get(id);
            if (t == null || t.arrived != 0L) return;
            t.arrived = now;
            t.bytes = bytes;
            t.failed = bytes < 0;
            settle(s);
        }
    }

    private static void settle(Switch s) {
        if (s.frame == 0L) return;
        for (Topic t : s.topics.values()) if (t.arrived == 0L) return;
        finish(s, false);
    }

    private static Double ms(long from, long to) {
        if (from == 0L || to == 0L) return null;
        return Math.round((to - from) / 10_000.0) / 100.0;
    }

    /** (under the lock) */
    private static void finish(Switch s, boolean cut) {
        if (s.done) return;
        s.done = true;
        if (on == s) on = null;
        List<Topic> topics = new ArrayList<>(s.topics.values());
        // Between frames, up to the one the page was handed to the display in.
        List<Long> frames = new ArrayList<>();
        for (long f : s.frames) if (s.frame == 0L || f <= s.frame) frames.add(f);
        List<Double> gaps = new ArrayList<>();
        for (int i = 1; i < frames.size(); i++) gaps.add(Math.round((frames.get(i) - frames.get(i - 1)) / 100_000.0) / 10.0);
        long at = System.currentTimeMillis() - (System.nanoTime() - s.tap) / 1_000_000L;
        new Thread(() -> {
            try {
                JSONObject e = new JSONObject();
                e.put("from", s.from != null ? s.from : JSONObject.NULL);
                e.put("to", s.to);
                e.put("first", s.first);
                if (s.awayMs != null) e.put("away_ms", s.awayMs);
                e.put("touched", s.touched);
                put(e, "place_ms", ms(s.tap, s.placed));
                // the end of the first frame's build that had the page (mbui builds and draws a frame on its GL thread),
                // and the main thread's next frame after it
                put(e, "composed_ms", ms(s.tap, s.built));
                put(e, "frame_ms", ms(s.tap, s.frame));
                e.put("cut", cut || s.frame == 0L);
                e.put("frames", frames.size());
                Double longest = null;
                for (Double g : gaps) if (longest == null || g > longest) longest = g;
                put(e, "longest_frame_ms", longest);
                JSONArray fg = new JSONArray();
                for (int i = 0; i < gaps.size() && i < 30; i++) fg.put(gaps.get(i));
                e.put("frame_gaps_ms", fg);
                e.put("topics_count", topics.size());
                JSONArray ts = new JSONArray();
                for (Topic t : topics) {
                    JSONObject j = new JSONObject();
                    j.put("topic", t.name);
                    // From the page subscribing it to the core's value taken on the UI's thread (decoded), from the tap.
                    put(j, "core_ms", ms(t.at, t.arrived));
                    put(j, "tap_shown_ms", ms(s.tap, t.arrived));
                    if (t.bytes >= 0) j.put("bytes", t.bytes);
                    if (t.failed) j.put("failed", true);
                    ts.put(j);
                }
                e.put("topics", ts);
                android.util.Log.i(TAG, "bar_switch " + e);
                send(at, e);
            } catch (Exception ignored) {
            }
        }).start();
    }

    private static void put(JSONObject o, String k, Double v) throws Exception {
        o.put(k, v != null ? v : JSONObject.NULL);
    }

    private static void send(long at, JSONObject properties) throws Exception {
        if (!Crashes.hasKey()) return;
        Context c = context;
        if (c == null) return;
        String account = Crashes.account(c);
        if (account == null) return;
        JSONObject p = new JSONObject(properties.toString());
        JSONObject d = Crashes.device();
        for (Iterator<String> k = d.keys(); k.hasNext(); ) {
            String key = k.next();
            p.put(key, d.get(key));
        }
        JSONObject event = new JSONObject().put("event", "bar_switch").put("distinct_id", account)
                .put("uuid", UUID.randomUUID().toString()).put("timestamp", Crashes.iso(at)).put("properties", p);
        List<JSONObject> batch;
        synchronized (waiting) {
            waiting.add(event);
            if (waiting.size() == 1) main.postDelayed(BarTiming::flush, BATCH_MS);
            if (waiting.size() < BATCH) return;
            batch = new ArrayList<>(waiting);
            waiting.clear();
        }
        try {
            Crashes.send(c, batch);
        } catch (Exception ignored) {
        }
    }

    private static void flush() {
        Context c = context;
        if (c == null) return;
        List<JSONObject> batch;
        synchronized (waiting) {
            batch = new ArrayList<>(waiting);
            waiting.clear();
        }
        if (!batch.isEmpty()) new Thread(() -> {
            try {
                Crashes.send(c, batch);
            } catch (Exception ignored) {
            }
        }).start();
    }

    /** The activity's window's callback, the touches seen on their way (Android's MainActivity.dispatchTouchEvent). */
    private static final class Touches implements Window.Callback {
        private final Window.Callback in;

        Touches(Window.Callback in) {
            this.in = in;
        }

        @Override public boolean dispatchTouchEvent(MotionEvent e) { touched(e); return in.dispatchTouchEvent(e); }
        @Override public boolean dispatchKeyEvent(KeyEvent e) { return in.dispatchKeyEvent(e); }
        @Override public boolean dispatchKeyShortcutEvent(KeyEvent e) { return in.dispatchKeyShortcutEvent(e); }
        @Override public boolean dispatchTrackballEvent(MotionEvent e) { return in.dispatchTrackballEvent(e); }
        @Override public boolean dispatchGenericMotionEvent(MotionEvent e) { return in.dispatchGenericMotionEvent(e); }
        @Override public boolean dispatchPopulateAccessibilityEvent(AccessibilityEvent e) { return in.dispatchPopulateAccessibilityEvent(e); }
        @Override public View onCreatePanelView(int f) { return in.onCreatePanelView(f); }
        @Override public boolean onCreatePanelMenu(int f, Menu m) { return in.onCreatePanelMenu(f, m); }
        @Override public boolean onPreparePanel(int f, View v, Menu m) { return in.onPreparePanel(f, v, m); }
        @Override public boolean onMenuOpened(int f, Menu m) { return in.onMenuOpened(f, m); }
        @Override public boolean onMenuItemSelected(int f, MenuItem i) { return in.onMenuItemSelected(f, i); }
        @Override public void onWindowAttributesChanged(WindowManager.LayoutParams a) { in.onWindowAttributesChanged(a); }
        @Override public void onContentChanged() { in.onContentChanged(); }
        @Override public void onWindowFocusChanged(boolean f) { in.onWindowFocusChanged(f); }
        @Override public void onAttachedToWindow() { in.onAttachedToWindow(); }
        @Override public void onDetachedFromWindow() { in.onDetachedFromWindow(); }
        @Override public void onPanelClosed(int f, Menu m) { in.onPanelClosed(f, m); }
        @Override public boolean onSearchRequested() { return in.onSearchRequested(); }
        @Override public boolean onSearchRequested(SearchEvent e) { return in.onSearchRequested(e); }
        @Override public ActionMode onWindowStartingActionMode(ActionMode.Callback c) { return in.onWindowStartingActionMode(c); }
        @Override public ActionMode onWindowStartingActionMode(ActionMode.Callback c, int t) { return in.onWindowStartingActionMode(c, t); }
        @Override public void onActionModeStarted(ActionMode m) { in.onActionModeStarted(m); }
        @Override public void onActionModeFinished(ActionMode m) { in.onActionModeFinished(m); }
        @Override public void onProvideKeyboardShortcuts(List<KeyboardShortcutGroup> d, Menu m, int id) { in.onProvideKeyboardShortcuts(d, m, id); }
        @Override public void onPointerCaptureChanged(boolean c) { in.onPointerCaptureChanged(c); }
    }
}
