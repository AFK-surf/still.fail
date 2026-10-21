package dev.mbui;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Reads the pairing dialog's code off Settings while 共享调试 pairs (docs/adb-share.md; still.fail's AdbCodeReader.kt),
 * so nobody types it: the dialog closes as soon as Settings is paused, a field popping up over it hides the code under
 * the keyboard, and Settings hides other apps' windows over it. An accessibility service, as only one may read another
 * app's window, turned on by the person (the 共享调试 page asks). It reads only Settings (res/xml/adb_code_reader.xml),
 * only while a pairing port is announced for this app's share (AdbShare.pairingPort), and the code goes nowhere but
 * the core's `adb.pair`, through AdbShareService, once per dialog.
 */
public final class AdbCodeReader extends AccessibilityService {
    /** The pairing port a code was read for: one try per dialog, a code that failed not tried again. */
    private int read = -1;

    @Override
    protected void onServiceConnected() {
        // the dialog is often open before its port is found (DNS-SD), and Settings says nothing more: looked at again then
        AdbShare.onPairingPort = this::look;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        look();
    }

    @Override
    public void onInterrupt() {}

    @Override
    public void onDestroy() {
        if (AdbShare.onPairingPort != null) AdbShare.onPairingPort = null;
        super.onDestroy();
    }

    private void look() {
        int port = AdbShare.pairingPort;
        if (port < 0 || port == read) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        String code = pairingCode(texts(root), port);
        if (code == null) return;
        read = port;
        AdbShare.read(this, code, port);
    }

    /** The words a window shows, all of them (a dialog's are few). */
    private static List<String> texts(AccessibilityNodeInfo root) {
        List<String> found = new ArrayList<>();
        walk(root, 0, found);
        return found;
    }

    private static void walk(AccessibilityNodeInfo node, int depth, List<String> found) {
        if (node.getText() != null) found.add(node.getText().toString());
        if (depth >= 32) return;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child != null) walk(child, depth + 1, found);
        }
    }

    private static final Pattern SIX = Pattern.compile("\\d(\\s*\\d){5}");

    /**
     * The pairing dialog's code among a window's words: six digits (spaced or not), in the window that shows the
     * pairing port too (its IP address & port), so no other number on a Settings page is taken for it; none when it is
     * not that one or the digits are not one number.
     */
    static String pairingCode(List<String> texts, int port) {
        Pattern at = Pattern.compile(":" + port + "(?!\\d)");
        boolean shown = false;
        for (String s : texts) if (at.matcher(s).find()) shown = true;
        if (!shown) return null;
        LinkedHashSet<String> codes = new LinkedHashSet<>();
        for (String s : texts) {
            String t = s.trim();
            if (SIX.matcher(t).matches()) codes.add(t.replaceAll("\\D", ""));
        }
        return codes.size() == 1 ? codes.iterator().next() : null;
    }
}
