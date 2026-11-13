package dev.mbui;

/** Runs on a JVM without Android; see scripts/ime_request_test.sh. */
public final class ImeRequestTest {
    private static int failures;

    private static void expect(String name, boolean actual, boolean expected) {
        if (actual != expected) {
            System.err.println("FAIL " + name + ": got " + actual + ", expected " + expected);
            failures++;
        }
    }

    public static void main(String[] args) {
        expect("focused split window without IME control requests it",
                ImeRequest.showNow(34, true, true, false, true), true);
        expect("API 30 split window requests without IME control",
                ImeRequest.showNow(30, true, true, false, true), true);
        expect("API 36 split window requests without IME control",
                ImeRequest.showNow(36, true, true, false, true), true);
        expect("tap retries a pending split-window request",
                ImeRequest.retryOnTap(true, false, true, true), true);

        for (int api : new int[] {29, 30, 34}) {
            for (boolean focused : new boolean[] {false, true}) {
                for (boolean controllable : new boolean[] {false, true}) {
                    for (boolean owed : new boolean[] {false, true}) {
                        expect("full screen api=" + api + " focused=" + focused + " controllable=" + controllable + " owed=" + owed,
                                ImeRequest.showNow(api, focused, false, controllable, owed),
                                owed && focused && (api < 30 || controllable));
                    }
                }
            }
        }
        expect("split window waits without focus", ImeRequest.showNow(34, false, true, false, true), false);
        expect("split window does not request without an owed show", ImeRequest.showNow(34, true, true, false, false), false);
        expect("tap without pending show still retries", ImeRequest.retryOnTap(true, false, false, false), true);
        expect("full screen keeps waiting for a pending show", ImeRequest.retryOnTap(true, false, true, false), false);
        expect("no tap does not retry", ImeRequest.retryOnTap(false, false, true, true), false);
        expect("visible keyboard does not retry", ImeRequest.retryOnTap(true, true, true, true), false);
        if (failures != 0) throw new AssertionError(failures + " IME request test(s) failed");
        System.out.println("IME request tests passed");
    }
}
