package dev.mbui;

/** The conditions under which the Android host asks the system to show the soft keyboard. */
final class ImeRequest {
    static boolean showNow(int api, boolean focused, boolean multiWindow, boolean controllable, boolean owed) {
        return owed && focused && (api < 30 || multiWindow || controllable);
    }

    static boolean retryOnTap(boolean lifted, boolean visible, boolean owed, boolean multiWindow) {
        return lifted && !visible && (!owed || multiWindow);
    }
}
