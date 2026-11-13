package dev.mbui;

import android.app.Activity;
import android.graphics.Rect;
import android.view.View;
import androidx.core.util.Consumer;
import androidx.window.core.layout.WindowSizeClass;
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter;
import androidx.window.layout.DisplayFeature;
import androidx.window.layout.FoldingFeature;
import androidx.window.layout.WindowInfoTracker;
import androidx.window.layout.WindowLayoutInfo;
import androidx.window.layout.WindowMetricsCalculator;

/**
 * What the system says of the window's room and of the device's pose, said to the app as it changes
 * (src/hostapi/system.mbt `size_class`, `fold`): what a layout is chosen by, never the view's width. The window's size
 * classes as Android defines them (Jetpack WindowManager's WindowSizeClass breakpoints: wide, compact under 600 dp,
 * medium under 840, expanded from there; high, compact under 480 dp, medium under 900, expanded from there), from the
 * window's bounds as WindowMetricsCalculator has them; the fold
 * WindowInfoTracker finds in the window (a FoldingFeature: HALF_OPENED said as `half`, FLAT as `open`, its bounds a
 * division while it separates the window, in the view's points), `none` once there is none in it (the outer screen of
 * a folded phone). A device that never had a fold in the window is said none of it.
 */
final class Folds {
    private final Activity activity;
    private final MBView view;
    private final WindowInfoTrackerCallbackAdapter tracker;
    private final Consumer<WindowLayoutInfo> took = this::took;
    /** What was last said (`size_class`, `fold`): null nothing yet. */
    private String saidClasses, saidFold;
    /** The window's layout as the tracker last said it: null none yet. */
    private WindowLayoutInfo layout;

    Folds(Activity activity, MBView view) {
        this.activity = activity;
        this.view = view;
        tracker = new WindowInfoTrackerCallbackAdapter(WindowInfoTracker.Companion.getOrCreate(activity));
    }

    /** While the activity is on screen: the fold's changes followed (the first said at once). */
    void start() {
        tracker.addWindowLayoutInfoListener(activity, Runnable::run, took);
        sizeClasses();
    }

    void stop() {
        tracker.removeWindowLayoutInfoListener(took);
    }

    private void took(WindowLayoutInfo info) {
        layout = info;
        sayFold();
    }

    /** The window laid out again (its insets applied, its configuration changed): its classes and the fold in it. */
    void laidOut() {
        sizeClasses();
        if (layout != null) sayFold();
    }

    private void sizeClasses() {
        Rect b = WindowMetricsCalculator.Companion.getOrCreate().computeCurrentWindowMetrics(activity).getBounds();
        float d = activity.getResources().getDisplayMetrics().density;
        if (b.isEmpty() || d <= 0) return;
        float w = b.width() / d, h = b.height() / d;
        String wide = w >= WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND ? "expanded"
                : w >= WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND ? "medium" : "compact";
        String tall = h >= WindowSizeClass.HEIGHT_DP_EXPANDED_LOWER_BOUND ? "expanded"
                : h >= WindowSizeClass.HEIGHT_DP_MEDIUM_LOWER_BOUND ? "medium" : "compact";
        String said = "{\"size_class\":{\"width\":\"" + wide + "\",\"height\":\"" + tall + "\"}}";
        if (said.equals(saidClasses)) return;
        saidClasses = said;
        Native.post("system", said);
        Host.log("size classes " + wide + " wide, " + tall + " high");
        Host.requestFrame();
    }

    private void sayFold() {
        String hinge = "none";
        StringBuilder divisions = new StringBuilder();
        int[] at = new int[2];
        view.getLocationInWindow(at);
        float d = view.density;
        for (DisplayFeature f : layout.getDisplayFeatures()) {
            if (!(f instanceof FoldingFeature)) continue;
            FoldingFeature fold = (FoldingFeature) f;
            hinge = fold.getState() == FoldingFeature.State.HALF_OPENED ? "half" : "open";
            if (!fold.isSeparating()) continue;
            Rect r = fold.getBounds();
            if (divisions.length() > 0) divisions.append(',');
            divisions.append(String.format(java.util.Locale.ROOT, "{\"x\":%.2f,\"y\":%.2f,\"w\":%.2f,\"h\":%.2f}",
                    (r.left - at[0]) / d, (r.top - at[1]) / d, r.width() / d, r.height() / d));
        }
        if (saidFold == null && hinge.equals("none")) return;
        String said = "{\"fold\":{\"hinge\":\"" + hinge + "\",\"divisions\":[" + divisions + "]}}";
        if (said.equals(saidFold)) return;
        saidFold = said;
        Native.post("system", said);
        Host.log("hinge " + hinge + ", divisions [" + divisions + "]");
        Host.requestFrame();
    }
}
