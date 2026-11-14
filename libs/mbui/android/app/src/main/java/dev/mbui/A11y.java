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
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * The app's widgets for Android's accessibility (TalkBack, and any service reading the screen), as Compose gives its
 * semantics: the view's virtual nodes, one a node the app told (src/ui/a11y.mbt's updates, @hostapi.a11y_tree: what
 * changed, kept by its number; those of no use of their own, flags v, none: what they hold their holder's), with their roles as Android's widgets' classes, their words, state and actions. A finger exploring the screen
 * (hover events) lands on the node under it; what a node is asked (a double tap: click) goes to the app on its
 * channel (@hostapi.a11y_channel) for its next frame. The accessibility focus is kept here, by node, as the app's
 * nodes keep their numbers from frame to frame.
 */
@SuppressWarnings("deprecation")
final class A11y extends AccessibilityNodeProvider {
    /** A node as the app told it (where it is from where its holder is), and what holds it. */
    static final class Node {
        int id, parent, widget;
        String role = "", flags = "", label = "", value = "", description = "", actions = "";
        float x, y, w, h;
        boolean range;
        float low, at, high;
        final List<Integer> kids = new ArrayList<>();
    }

    private final MBView view;
    private final Map<Integer, Node> nodes = new HashMap<>();
    /** The node with the keyboard's focus, as the app told it (0: none); `focused` is the accessibility focus. */
    private int inputFocus;
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

    /**
     * What the app told of its widgets now (main thread): an update (src/ui/a11y.mbt's head: the nodes that changed,
     * each whole, and which has the keyboard's focus), kept; one in nothing that holds it gone with what it holds; the
     * services told the view changed. One that is not whole coming to none kept (the view made again under an app that
     * told it all before) asks for all of it again.
     */
    void set(String update) {
        String[] lines = update.split("\n");
        String[] head = lines.length > 0 ? lines[0].split("\u001f", -1) : new String[0];
        if (head.length < 3 || !head[0].equals("T")) return;
        boolean full = head[1].equals("1");
        if (!full && nodes.isEmpty()) {
            Native.post("a11y", "{\"action\":\"resend\"}");
            return;
        }
        if (full) nodes.clear();
        try {
            inputFocus = Integer.parseInt(head[2]);
        } catch (NumberFormatException e) {
            inputFocus = 0;
        }
        List<Node> told = new ArrayList<>();
        Set<Integer> held = new HashSet<>();
        List<Integer> letGo = new ArrayList<>();
        for (int i = 1; i < lines.length; i++) {
            String[] f = lines[i].split("\u001f", -1);
            if (f.length < 17 || !f[0].equals("N")) continue;
            try {
                Node n = new Node();
                n.id = Integer.parseInt(f[1]);
                n.role = f[2];
                n.flags = f[3];
                n.x = Float.parseFloat(f[4]);
                n.y = Float.parseFloat(f[5]);
                n.w = Float.parseFloat(f[6]);
                n.h = Float.parseFloat(f[7]);
                n.label = f[8];
                n.value = f[9];
                n.description = f[10];
                if (!f[12].isEmpty()) {
                    n.range = true;
                    n.low = Float.parseFloat(f[11]);
                    n.at = Float.parseFloat(f[12]);
                    n.high = Float.parseFloat(f[13]);
                }
                n.actions = f[14];
                n.widget = Integer.parseInt(f[15]);
                if (!f[16].isEmpty()) for (String k : f[16].split(",")) n.kids.add(Integer.parseInt(k));
                Node was = nodes.get(n.id);
                if (was != null) {
                    n.parent = was.parent;
                    for (int k : was.kids) if (!n.kids.contains(k)) letGo.add(k);
                }
                held.addAll(n.kids);
                nodes.put(n.id, n);
                told.add(n);
            } catch (NumberFormatException e) {
                Host.log("a11y: a line not read: " + e);
            }
        }
        for (Node n : told) for (int k : n.kids) {
            Node c = nodes.get(k);
            if (c != null) c.parent = n.id;
        }
        // (one in nothing told holds: gone, with what it holds)
        while (!letGo.isEmpty()) {
            int k = letGo.remove(letGo.size() - 1);
            if (held.contains(k)) continue;
            Node n = nodes.remove(k);
            if (n != null) letGo.addAll(n.kids);
        }
        if (focused != HOST_VIEW_ID && !nodes.containsKey(focused)) focused = HOST_VIEW_ID;
        if (hovered != HOST_VIEW_ID && !nodes.containsKey(hovered)) hovered = HOST_VIEW_ID;
        AccessibilityEvent e = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED);
        e.setContentChangeTypes(AccessibilityEvent.CONTENT_CHANGE_TYPE_SUBTREE);
        e.setPackageName(view.getContext().getPackageName());
        e.setSource(view);
        ViewParent parent = view.getParent();
        if (parent != null) parent.requestSendAccessibilityEvent(view, e);
    }

    /** What node `id` holds as virtual nodes: those of no use of their own (flags v) left out, what they hold in place. */
    private List<Integer> shownKids(int id) {
        List<Integer> out = new ArrayList<>();
        Node n = nodes.get(id);
        if (n == null) return out;
        for (int k : n.kids) {
            Node c = nodes.get(k);
            if (c == null) continue;
            if (has(c.flags, 'v')) out.addAll(shownKids(k));
            else out.add(k);
        }
        return out;
    }

    /** The virtual node that holds `n`: its nearest holder of use of its own (0: the view). */
    private int shownHolder(Node n) {
        Node p = nodes.get(n.parent);
        while (p != null && p.id != 0 && has(p.flags, 'v')) p = nodes.get(p.parent);
        return p == null ? 0 : p.id;
    }

    /** Where `n` is in the view (points): its holders' places and its own, each from where its holder is. */
    private float[] placeOf(Node n) {
        float x = n.x, y = n.y;
        for (Node p = nodes.get(n.parent); p != null && p.id != 0; p = nodes.get(p.parent)) {
            x += p.x;
            y += p.y;
        }
        return new float[] {x, y};
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
        float[] p = placeOf(n);
        return new Rect(at[0] + Math.round(p[0] * d), at[1] + Math.round(p[1] * d),
                at[0] + Math.round((p[0] + n.w) * d), at[1] + Math.round((p[1] + n.h) * d));
    }

    @Override
    public AccessibilityNodeInfo createAccessibilityNodeInfo(int id) {
        if (id == HOST_VIEW_ID) {
            AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(view);
            view.onInitializeAccessibilityNodeInfo(info);
            for (int r : shownKids(0)) info.addChild(view, r);
            return info;
        }
        Node n = nodes.get(id);
        if (n == null) return null;
        AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(view, id);
        info.setPackageName(view.getContext().getPackageName());
        info.setClassName(classOf(n.role));
        int holder = shownHolder(n);
        if (holder != 0) info.setParent(view, holder);
        else info.setParent(view);
        for (int k : shownKids(id)) info.addChild(view, k);
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
        info.setFocused(inputFocus == id);
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
        if (has(n.actions, 't')) {
            info.setEditable(true);
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT);
        }
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
            case AccessibilityNodeInfo.ACTION_SET_TEXT: {
                // words put in the field in place of what it held (the app's next frame, as typed)
                CharSequence t = arguments == null ? null
                        : arguments.getCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE);
                if (!has(n.actions, 't') || n.widget == 0) return false;
                Native.post("a11y", "{\"id\":" + n.widget + ",\"action\":\"set_text\",\"text\":"
                        + org.json.JSONObject.quote(t == null ? "" : t.toString()) + "}");
                return true;
            }
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
            if (n.id == 0 || has(n.flags, 'v')) continue;
            float[] p = placeOf(n);
            if (x < p[0] || y < p[1] || x >= p[0] + n.w || y >= p[1] + n.h) continue;
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
