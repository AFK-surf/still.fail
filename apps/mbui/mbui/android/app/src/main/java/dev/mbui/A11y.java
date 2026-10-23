package dev.mbui;

import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeProvider;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The app's widgets for Android's accessibility (TalkBack, and any service reading the screen), as Compose gives its
 * semantics: the view's virtual nodes, one a line of what the app last said (src/ui/a11y.mbt, @hostapi.a11y_tree),
 * with their roles as Android's widgets' classes, their words, state and actions. A finger exploring the screen
 * (hover events) lands on the node under it; what a node is asked (a double tap: click) goes to the app on its
 * channel (@hostapi.a11y_channel) for its next frame. The accessibility focus is kept here, by node, as the app's
 * nodes keep their numbers from frame to frame.
 */
@SuppressWarnings("deprecation")
final class A11y extends AccessibilityNodeProvider {
    /** A node as the app said it. */
    static final class Node {
        int id, parent, widget;
        String role = "", flags = "", label = "", value = "", description = "", actions = "";
        float x, y, w, h;
        boolean range;
        float low, at, high;
        final List<Integer> kids = new ArrayList<>();
    }

    private final MBView view;
    private Map<Integer, Node> nodes = new HashMap<>();
    private List<Integer> roots = new ArrayList<>();
    private int focused = HOST_VIEW_ID;
    private int hovered = HOST_VIEW_ID;

    A11y(MBView view) {
        this.view = view;
    }

    /** Whether a service reads the screen (@hostapi.a11y_on): the app tells its widgets only then. */
    static boolean on() {
        MainActivity a = Host.activity;
        if (a == null) return false;
        AccessibilityManager m = (AccessibilityManager) a.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE);
        return m != null && m.isEnabled();
    }

    /** What the app said its widgets are now (main thread): the nodes made anew, the services told the view changed. */
    void set(String lines) {
        Map<Integer, Node> next = new HashMap<>();
        List<Integer> top = new ArrayList<>();
        for (String line : lines.split("\n")) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\u001f", -1);
            if (f.length < 16) continue;
            try {
                Node n = new Node();
                n.id = Integer.parseInt(f[0]);
                n.parent = Integer.parseInt(f[1]);
                n.widget = Integer.parseInt(f[2]);
                n.role = f[3];
                n.flags = f[4];
                n.x = Float.parseFloat(f[5]);
                n.y = Float.parseFloat(f[6]);
                n.w = Float.parseFloat(f[7]);
                n.h = Float.parseFloat(f[8]);
                n.label = f[9];
                n.value = f[10];
                n.description = f[11];
                if (!f[12].isEmpty()) {
                    n.range = true;
                    n.low = Float.parseFloat(f[12]);
                    n.at = Float.parseFloat(f[13]);
                    n.high = Float.parseFloat(f[14]);
                }
                n.actions = f[15];
                next.put(n.id, n);
                Node p = next.get(n.parent);
                if (p != null) p.kids.add(n.id);
                else top.add(n.id);
            } catch (NumberFormatException e) {
                Host.log("a11y: a line not read: " + e);
            }
        }
        nodes = next;
        roots = top;
        if (focused != HOST_VIEW_ID && !nodes.containsKey(focused)) focused = HOST_VIEW_ID;
        if (hovered != HOST_VIEW_ID && !nodes.containsKey(hovered)) hovered = HOST_VIEW_ID;
        AccessibilityEvent e = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED);
        e.setContentChangeTypes(AccessibilityEvent.CONTENT_CHANGE_TYPE_SUBTREE);
        e.setPackageName(view.getContext().getPackageName());
        e.setSource(view);
        ViewParent parent = view.getParent();
        if (parent != null) parent.requestSendAccessibilityEvent(view, e);
    }

    boolean any() {
        return !nodes.isEmpty();
    }

    private static boolean has(String s, char c) {
        return s.indexOf(c) >= 0;
    }

    /** Android's widget class for a role, what TalkBack names it by ("button", "checkbox", …). */
    private static String classOf(String role) {
        switch (role) {
            case "Button":
            case "Tab":
            case "MenuItem":
            case "Option":
                return "android.widget.Button";
            case "Checkbox":
            case "MenuItemCheckbox":
                return "android.widget.CheckBox";
            case "Switch":
                return "android.widget.Switch";
            case "Radio":
            case "MenuItemRadio":
                return "android.widget.RadioButton";
            case "Slider":
                return "android.widget.SeekBar";
            case "ProgressBar":
                return "android.widget.ProgressBar";
            case "Image":
                return "android.widget.ImageView";
            case "TextField":
                return "android.widget.EditText";
            case "Combobox":
                return "android.widget.Spinner";
            case "ScrollArea":
                return "android.widget.ScrollView";
            case "TabList":
                return "android.widget.TabWidget";
            case "Text":
            case "Heading":
            case "Link":
            case "Status":
                return "android.widget.TextView";
            default:
                return "android.view.View";
        }
    }

    private Rect onScreen(Node n) {
        int[] at = new int[2];
        view.getLocationOnScreen(at);
        float d = view.density;
        return new Rect(at[0] + Math.round(n.x * d), at[1] + Math.round(n.y * d),
                at[0] + Math.round((n.x + n.w) * d), at[1] + Math.round((n.y + n.h) * d));
    }

    @Override
    public AccessibilityNodeInfo createAccessibilityNodeInfo(int id) {
        if (id == HOST_VIEW_ID) {
            AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(view);
            view.onInitializeAccessibilityNodeInfo(info);
            for (int r : roots) info.addChild(view, r);
            return info;
        }
        Node n = nodes.get(id);
        if (n == null) return null;
        AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(view, id);
        info.setPackageName(view.getContext().getPackageName());
        info.setClassName(classOf(n.role));
        if (n.parent != 0 && nodes.containsKey(n.parent)) info.setParent(view, n.parent);
        else info.setParent(view);
        for (int k : n.kids) info.addChild(view, k);
        Rect r = onScreen(n);
        info.setBoundsInScreen(r);
        Rect shown = new Rect();
        info.setVisibleToUser(view.getGlobalVisibleRect(shown) && Rect.intersects(shown, r));
        boolean words = n.role.equals("Text") || n.role.equals("Heading") || n.role.equals("Link") || n.role.equals("Status");
        if (n.role.equals("TextField")) {
            info.setText(n.value);
            info.setHintText(n.label);
            info.setEditable(true);
            info.setFocusable(true);
        } else if (words) {
            info.setText(n.label);
        } else if (!n.label.isEmpty()) {
            info.setContentDescription(n.label);
        }
        if (n.role.equals("Heading") && Build.VERSION.SDK_INT >= 28) info.setHeading(true);
        if (!n.value.isEmpty() && !n.role.equals("TextField") && Build.VERSION.SDK_INT >= 30) info.setStateDescription(n.value);
        if (!n.description.isEmpty() && Build.VERSION.SDK_INT >= 30) info.setTooltipText(n.description);
        info.setCheckable(has(n.flags, 'c'));
        info.setChecked(has(n.flags, 'C'));
        info.setSelected(has(n.flags, 's'));
        info.setEnabled(!has(n.flags, 'd'));
        info.setFocused(has(n.flags, 'f'));
        if (n.range) info.setRangeInfo(AccessibilityNodeInfo.RangeInfo.obtain(AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_FLOAT, n.low, n.high, n.at));
        boolean click = has(n.actions, 'a');
        info.setClickable(click);
        if (click || has(n.actions, 'f') || n.role.equals("TextField")) info.setFocusable(true);
        if (click) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK);
        if (has(n.actions, 'i')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD);
        if (has(n.actions, 'd')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD);
        if (has(n.actions, 'e')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_EXPAND);
        if (has(n.actions, 'c')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_COLLAPSE);
        if (has(n.actions, 'x')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_DISMISS);
        if (has(n.actions, 'f')) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_FOCUS);
        info.setAccessibilityFocused(focused == id);
        info.addAction(focused == id ? AccessibilityNodeInfo.AccessibilityAction.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                : AccessibilityNodeInfo.AccessibilityAction.ACTION_ACCESSIBILITY_FOCUS);
        return info;
    }

    @Override
    public AccessibilityNodeInfo findFocus(int focus) {
        if (focus == AccessibilityNodeInfo.FOCUS_ACCESSIBILITY && focused != HOST_VIEW_ID) return createAccessibilityNodeInfo(focused);
        return null;
    }

    @Override
    public boolean performAction(int id, int action, Bundle arguments) {
        if (id == HOST_VIEW_ID) return view.performAccessibilityAction(action, arguments);
        Node n = nodes.get(id);
        if (n == null) return false;
        switch (action) {
            case AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS:
                if (focused == id) return false;
                if (focused != HOST_VIEW_ID) send(focused, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED);
                focused = id;
                view.invalidate();
                send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED);
                return true;
            case AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS:
                if (focused != id) return false;
                focused = HOST_VIEW_ID;
                view.invalidate();
                send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED);
                return true;
            case AccessibilityNodeInfo.ACTION_CLICK:
                return ask(n, "activate", 'a');
            case AccessibilityNodeInfo.ACTION_SCROLL_FORWARD:
                return ask(n, "increment", 'i');
            case AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD:
                return ask(n, "decrement", 'd');
            case AccessibilityNodeInfo.ACTION_EXPAND:
                return ask(n, "expand", 'e');
            case AccessibilityNodeInfo.ACTION_COLLAPSE:
                return ask(n, "collapse", 'c');
            case AccessibilityNodeInfo.ACTION_DISMISS:
                return ask(n, "dismiss", 'x');
            case AccessibilityNodeInfo.ACTION_FOCUS:
                return ask(n, "focus", 'f');
            default:
                return false;
        }
    }

    /** An action the node takes, asked of its widget for the app's next frame. */
    private boolean ask(Node n, String action, char letter) {
        if (!has(n.actions, letter) || n.widget == 0) return false;
        Native.post("a11y", "{\"id\":" + n.widget + ",\"action\":\"" + action + "\"}");
        if (action.equals("activate")) send(n.id, AccessibilityEvent.TYPE_VIEW_CLICKED);
        return true;
    }

    private void send(int id, int type) {
        Node n = nodes.get(id);
        AccessibilityEvent e = AccessibilityEvent.obtain(type);
        e.setPackageName(view.getContext().getPackageName());
        e.setSource(view, id);
        if (n != null) {
            e.setClassName(classOf(n.role));
            if (!n.label.isEmpty()) e.getText().add(n.label);
        }
        ViewParent parent = view.getParent();
        if (parent != null) parent.requestSendAccessibilityEvent(view, e);
    }

    /**
     * A finger exploring the screen (touch exploration's hover events, in the view's pixels): the node under it, the
     * innermost that is read out (one that takes an action or has words), entered; false where there is none.
     */
    boolean hover(MotionEvent e) {
        if (nodes.isEmpty()) return false;
        float x = e.getX() / view.density, y = e.getY() / view.density;
        int at = HOST_VIEW_ID;
        float area = Float.MAX_VALUE;
        for (Node n : nodes.values()) {
            if (x < n.x || y < n.y || x >= n.x + n.w || y >= n.y + n.h) continue;
            boolean read = !n.actions.isEmpty() || !n.label.isEmpty() || !n.value.isEmpty();
            if (!read) continue;
            float a = n.w * n.h;
            if (a < area) {
                area = a;
                at = n.id;
            }
        }
        switch (e.getAction()) {
            case MotionEvent.ACTION_HOVER_ENTER:
            case MotionEvent.ACTION_HOVER_MOVE:
                if (at != hovered) {
                    int was = hovered;
                    hovered = at;
                    if (at != HOST_VIEW_ID) send(at, AccessibilityEvent.TYPE_VIEW_HOVER_ENTER);
                    if (was != HOST_VIEW_ID) send(was, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT);
                }
                return at != HOST_VIEW_ID;
            case MotionEvent.ACTION_HOVER_EXIT:
                if (hovered != HOST_VIEW_ID) send(hovered, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT);
                hovered = HOST_VIEW_ID;
                return true;
            default:
                return false;
        }
    }
}
