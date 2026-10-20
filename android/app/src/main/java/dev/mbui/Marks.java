package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Marks drawn onto an image at its own size, as a PNG (src/host/marks.mbt), as still.fail's Android app's ImageMarks.kt
 * draws them (drawMarks, drawPins): strokes round-capped, a box with rounded corners, an arrow's two barbs, a line drawn
 * by hand smoothed through its midpoints, words edged in their halo, the numbered marks' pins. Off the main thread;
 * MoonBit asks after each every frame (android_host.c).
 */
final class Marks {
    static final class Job {
        volatile int state;  // 0 drawing, 1 made, -1 failed
        volatile byte[] png = new byte[0];
    }

    static final ConcurrentHashMap<Integer, Job> jobs = new ConcurrentHashMap<>();
    private static int next = 1;
    private static final float LINE = 3f;
    private static final float BASELINE = 0.98f;

    static synchronized int start(byte[] image, String marks) {
        int id = next++;
        Job j = new Job();
        jobs.put(id, j);
        new Thread(() -> {
            Bitmap b = null;
            try {
                BitmapFactory.Options o = new BitmapFactory.Options();
                o.inMutable = true;
                o.inPreferredConfig = Bitmap.Config.ARGB_8888;
                b = BitmapFactory.decodeByteArray(image, 0, image.length, o);
                if (b == null) throw new IllegalStateException("the image could not be decoded");
                if (!b.isMutable()) {
                    Bitmap m = b.copy(Bitmap.Config.ARGB_8888, true);
                    b.recycle();
                    b = m;
                }
                JSONObject v = new JSONObject(marks);
                Canvas canvas = new Canvas(b);
                double w = v.optDouble("w", b.getWidth()), h = v.optDouble("h", b.getHeight());
                canvas.scale((float) (b.getWidth() / Math.max(1, w)), (float) (b.getHeight() / Math.max(1, h)));
                draw(canvas, v.getJSONArray("marks"), (float) w, (float) h);
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                b.compress(Bitmap.CompressFormat.PNG, 100, out);
                j.png = out.toByteArray();
                j.state = 1;
                Host.log("marks: " + v.getJSONArray("marks").length() + " drawn on " + b.getWidth() + "x" + b.getHeight() + " (" + j.png.length + " bytes)");
            } catch (Throwable e) {
                Host.log("marks: " + e);
                j.state = -1;
            } finally {
                if (b != null) b.recycle();
            }
            Native.tell(Native.OUTSIDE_MARKS, id, j.state);
        }, "mbui-marks").start();
        return id;
    }

    static int state(int id) {
        Job j = jobs.get(id);
        return j == null ? -1 : j.state;
    }

    static byte[] png(int id) {
        Job j = jobs.remove(id);
        return j == null ? new byte[0] : j.png;
    }

    private static int color(JSONObject m, String k) {
        long rgba = (long) m.optDouble(k, 0xE5704AFFL);
        return (int) (((rgba & 0xFF) << 24) | ((rgba >> 8) & 0xFFFFFF));
    }

    private static void draw(Canvas canvas, JSONArray marks, float natW, float natH) throws Exception {
        Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
        line.setStyle(Paint.Style.STROKE);
        line.setStrokeCap(Paint.Cap.ROUND);
        line.setStrokeJoin(Paint.Join.ROUND);
        Paint words = new Paint(Paint.ANTI_ALIAS_FLAG);
        words.setTypeface(Typeface.create(Typeface.DEFAULT, 600, false));
        for (int i = 0; i < marks.length(); i++) {
            JSONObject m = marks.getJSONObject(i);
            String kind = m.getString("kind");
            float w = (float) m.getDouble("w");
            JSONArray p = m.getJSONArray("pts");
            if (kind.equals("words")) {
                String text = m.optString("text");
                float x = (float) p.getDouble(0), y = (float) p.getDouble(1);
                words.setTextSize(w);
                words.setStyle(Paint.Style.STROKE);
                words.setStrokeWidth(w * 0.22f);
                words.setStrokeJoin(Paint.Join.ROUND);
                words.setColor(color(m, "halo"));
                canvas.drawText(text, x, y + w * BASELINE, words);
                words.setStyle(Paint.Style.FILL);
                words.setColor(color(m, "color"));
                canvas.drawText(text, x, y + w * BASELINE, words);
                continue;
            }
            line.setColor(color(m, "color"));
            line.setStrokeWidth(w);
            Path path = new Path();
            if (kind.equals("box")) {
                float ax = (float) p.getDouble(0), ay = (float) p.getDouble(1), bx = (float) p.getDouble(2), by = (float) p.getDouble(3);
                float x = Math.min(ax, bx), y = Math.min(ay, by), bw = Math.abs(bx - ax), bh = Math.abs(by - ay);
                float r = Math.min(w * 1.5f, Math.min(bw / 2, bh / 2));
                path.addRoundRect(x, y, x + bw, y + bh, r, r, Path.Direction.CW);
            } else if (kind.equals("arrow")) {
                float ax = (float) p.getDouble(0), ay = (float) p.getDouble(1), bx = (float) p.getDouble(2), by = (float) p.getDouble(3);
                float dx = bx - ax, dy = by - ay, len = (float) Math.hypot(dx, dy);
                if (len <= 0) len = 1;
                float ux = dx / len, uy = dy / len, size = Math.min(w * 5, len * 0.6f), spread = 0.5f;
                float backX = bx - ux * size, backY = by - uy * size;
                path.moveTo(ax, ay);
                path.lineTo(bx, by);
                path.moveTo(backX - uy * size * spread, backY + ux * size * spread);
                path.lineTo(bx, by);
                path.lineTo(backX + uy * size * spread, backY - ux * size * spread);
            } else {
                int n = p.length() / 2;
                if (n == 0) continue;
                path.moveTo((float) p.getDouble(0), (float) p.getDouble(1));
                if (n < 3) {
                    for (int k = 1; k < n; k++) path.lineTo((float) p.getDouble(2 * k), (float) p.getDouble(2 * k + 1));
                } else {
                    // through the midpoints, each point bending the line: smooth, however jerky the finger
                    for (int k = 1; k < n - 1; k++) {
                        float x = (float) p.getDouble(2 * k), y = (float) p.getDouble(2 * k + 1);
                        float nx = (float) p.getDouble(2 * k + 2), ny = (float) p.getDouble(2 * k + 3);
                        path.quadTo(x, y, (x + nx) / 2, (y + ny) / 2);
                    }
                    path.lineTo((float) p.getDouble(2 * n - 2), (float) p.getDouble(2 * n - 1));
                }
            }
            canvas.drawPath(path, line);
        }
        pins(canvas, marks, natW, natH);
    }

    /** The numbered marks' pins (ImageMarks.kt drawPins): up and to the right of the point, kept within the image. */
    private static void pins(Canvas canvas, JSONArray marks, float natW, float natH) throws Exception {
        Paint pin = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        text.setTypeface(Typeface.create(Typeface.DEFAULT, 650, false));
        text.setTextAlign(Paint.Align.CENTER);
        for (int i = 0; i < marks.length(); i++) {
            JSONObject m = marks.getJSONObject(i);
            int n = m.optInt("n", 0);
            if (n <= 0) continue;
            float k = (float) m.getDouble("w") / LINE;
            JSONArray p = m.getJSONArray("pts");
            float px, py;
            if (m.getString("kind").equals("box")) {
                px = (float) Math.min(p.getDouble(0), p.getDouble(2));
                py = (float) Math.min(p.getDouble(1), p.getDouble(3));
            } else {
                px = (float) p.getDouble(0);
                py = (float) p.getDouble(1);
            }
            px = Math.max(2 * k, Math.min(Math.max(2 * k, natW - 22 * k), px));
            py = Math.max(22 * k, Math.min(Math.max(22 * k, natH - 2 * k), py));
            float x = px - 2 * k, y = py - 22 * k, size = 24 * k, edge = 2 * k;
            int halo = color(m, "halo");
            pin.setColor(halo);
            pin.setShadowLayer(3 * k, 0f, 2 * k, android.graphics.Color.argb(56, 0, 0, 0));
            canvas.drawPath(shape(x, y, size, 0, 12 * k, 3 * k), pin);
            pin.clearShadowLayer();
            pin.setColor(color(m, "color"));
            canvas.drawPath(shape(x, y, size, edge, 10 * k, 1.5f * k), pin);
            text.setColor(halo);
            text.setTextSize(11 * k);
            float mid = y + size / 2 - (text.descent() + text.ascent()) / 2;
            canvas.drawText(Integer.toString(n), x + size / 2, mid, text);
        }
    }

    private static Path shape(float x, float y, float size, float inset, float r, float point) {
        Path s = new Path();
        s.addRoundRect(new RectF(x + inset, y + inset, x + size - inset, y + size - inset),
                new float[] {r, r, r, r, r, r, point, point}, Path.Direction.CW);
        return s;
    }
}
