package dev.mbui;

import android.graphics.Rect;
import android.text.InputType;
import android.util.SparseArray;
import android.view.View;
import android.view.ViewStructure;
import android.view.autofill.AutofillManager;
import android.view.autofill.AutofillValue;

/**
 * A login of a site the app does not hold itself, from the system's autofill service (mbui/hostapi {@code autofill},
 * src/hostapi/autofill.mbt): what a browser does for its pages. While the app asks, {@link MBView} says it holds a login
 * form of that site (two virtual fields, an account and a password, under the site's web domain), and the autofill
 * service (1Password, Google's, whichever the person chose in the system's settings) is asked for it as the person
 * asked: it offers its logins for the site there and fills the one picked into the form, which keeps it here until
 * the app takes it (once). Nothing is kept after: the ask ends with the session cancelled, so nothing is offered to be
 * saved. Called from the GL thread; the autofill manager on the main one.
 */
final class Autofills {
    /** The fields' virtual ids under the view. */
    static final int USERNAME = 1, PASSWORD = 2;

    /** The site asked for (its host), while it is: null, none. */
    private static volatile String host;
    /** The login picked, until taken: host, account and password, each ended by a unit separator; "" none. */
    private static volatile String picked = "";

    private Autofills() {}

    private static AutofillManager manager(View v) {
        return v == null ? null : v.getContext().getSystemService(AutofillManager.class);
    }

    /** 1 where there is an autofill service to ask (one chosen in the system's settings). */
    static int able() {
        AutofillManager m = manager(Host.view);
        return m != null && m.isEnabled() ? 1 : 0;
    }

    /** Asks the autofill service for a login of {@code h}: 0 where there is none to ask. */
    static int ask(String h) {
        MBView v = Host.view;
        AutofillManager m = manager(v);
        if (m == null || !m.isEnabled() || h == null || h.isEmpty()) return 0;
        host = h;
        picked = "";
        Host.main.post(() -> {
            if (Host.view != v || !h.equals(host)) return;
            // a session already open (an ask before) is ended, so the service reads the form anew, with this site
            m.cancel();
            v.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_YES);
            m.requestAutofill(v, USERNAME, bounds(v, USERNAME));
        });
        return 1;
    }

    /** The login picked, once: "" until one is. */
    static String take() {
        String p = picked;
        picked = "";
        return p;
    }

    /** Lets go of the ask: the service's offer withdrawn, nothing kept. */
    static void end() {
        if (host == null) return;
        host = null;
        picked = "";
        MBView v = Host.view;
        Host.main.post(() -> {
            AutofillManager m = manager(v);
            if (m != null && host == null) m.cancel();
            if (v != null && host == null) v.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_AUTO);
        });
    }

    /** Where a field is said to be (the service shows its offer by it): at the view's foot, where the app offers it. */
    private static Rect bounds(View v, int id) {
        int w = v.getWidth(), h = v.getHeight(), row = Math.max(1, h / 16);
        int top = h - row * (id == USERNAME ? 3 : 2);
        return new Rect(0, top, w, top + row);
    }

    /** The view's part of the structure the service reads (MBView.onProvideAutofillVirtualStructure). */
    static void provide(View v, ViewStructure s) {
        String h = host;
        if (h == null) return;
        s.setClassName("android.webkit.WebView");
        s.setWebDomain(h);
        s.setChildCount(2);
        field(v, s, 0, USERNAME, h, View.AUTOFILL_HINT_USERNAME, "text", "username",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        field(v, s, 1, PASSWORD, h, View.AUTOFILL_HINT_PASSWORD, "password", "password",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    }

    private static void field(View v, ViewStructure s, int index, int id, String h, String hint, String type,
                              String name, int input) {
        ViewStructure f = s.newChild(index);
        f.setAutofillId(s.getAutofillId(), id);
        f.setAutofillType(View.AUTOFILL_TYPE_TEXT);
        f.setAutofillHints(new String[] {hint});
        f.setInputType(input);
        f.setClassName("android.widget.EditText");
        f.setWebDomain(h);
        f.setHtmlInfo(f.newHtmlInfoBuilder("input").addAttribute("type", type).addAttribute("name", name)
                .addAttribute("autocomplete", id == USERNAME ? "username" : "current-password").build());
        f.setDataIsSensitive(id == PASSWORD);
        f.setVisibility(View.VISIBLE);
        f.setEnabled(true);
        f.setFocusable(true);
        f.setFocused(id == USERNAME);
        Rect r = bounds(v, id);
        f.setDimens(r.left, r.top, 0, 0, r.width(), r.height());
    }

    /** What the service filled (MBView.autofill): kept until taken, a frame asked for. */
    static void filled(SparseArray<AutofillValue> values) {
        String h = host;
        if (h == null) return;
        String user = text(values.get(USERNAME)), pass = text(values.get(PASSWORD));
        if (user.isEmpty() && pass.isEmpty()) return;
        picked = h + "\u001f" + user + "\u001f" + pass + "\u001f";
        Host.requestFrame();
        // the session ended now: the form holds nothing the service would offer to save
        AutofillManager m = manager(Host.view);
        if (m != null) m.cancel();
    }

    private static String text(AutofillValue v) {
        return v != null && v.isText() ? v.getTextValue().toString() : "";
    }
}
