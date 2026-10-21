// Compose's animation arithmetic, as its own classes compute it (scripts/compose_ref.sh).
import androidx.compose.animation.core.*;

public class ComposeRef {
    static void spring(String name, float ratio, float k, float thr, float from, float to, float v) {
        FloatSpringSpec s = new FloatSpringSpec(ratio, k, thr);
        long dur = s.getDurationNanos(from, to, v) / 1_000_000L;
        StringBuilder b = new StringBuilder("SPRING " + name + " dur=" + dur);
        for (long ms : new long[]{0, 16, 33, 50, 100, 150, 200, 300}) {
            b.append(" ").append(ms).append("=").append(s.getValueFromNanos(ms * 1_000_000L, from, to, v));
        }
        System.out.println(b);
    }

    static void tween(String name, int ms, int delay, Easing e) {
        FloatTweenSpec s = new FloatTweenSpec(ms, delay, e);
        StringBuilder b = new StringBuilder("TWEEN " + name);
        for (long t : new long[]{0, 16, 50, 100, 150, 200, 250, 300, 400}) {
            b.append(" ").append(t).append("=").append(s.getValueFromNanos(t * 1_000_000L, 0f, 1f, 0f));
        }
        System.out.println(b);
    }

    public static void main(String[] a) {
        spring("default", 1f, 1500f, 0.01f, 0f, 1f, 0f);
        spring("row100", 1f, 350f, 1f, 100f, 0f, 0f);
        spring("row-66", 1f, 350f, 1f, -66f, 0f, 0f);
        float move = (float) Math.pow(2 * Math.PI / (1.2 * 0.28), 2);
        spring("move66", 1f, move, 0.5f, 66f, 0f, 0f);
        float menu = (float) Math.pow(2 * Math.PI / (1.2 * 0.24), 2);
        spring("menu", 0.92f, menu, 0.001f, 0.9f, 1f, 0f);
        float sheet = (float) Math.pow(2 * Math.PI / (1.2 * 0.32), 2);
        spring("sheet600", 1f, sheet, 0.5f, 600f, 0f, 0f);
        spring("sheetfling", 1f, sheet, 0.5f, 300f, 600f, 3000f);
        spring("over", 1.5f, 400f, 0.01f, 1f, 0f, 0f);
        spring("bouncy", 0.5f, 300f, 0.01f, 0f, 1f, 0f);
        spring("glide", 1f, 300f, 1f, 80f, 0f, 0f);
        tween("std300", 300, 0, EasingKt.getFastOutSlowInEasing());
        tween("arrive240d100", 240, 100, new CubicBezierEasing(0.2f, 0.7f, 0.2f, 1f));
        tween("css180", 180, 0, new CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f));
        tween("flight600", 600, 0, new CubicBezierEasing(0.6f, 0f, 0.2f, 1f));
        tween("linear160", 160, 0, EasingKt.getLinearEasing());
    }
}
