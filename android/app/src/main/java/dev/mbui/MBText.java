package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.icu.text.Bidi;
import android.icu.text.BreakIterator;
import android.opengl.GLES30;
import android.opengl.GLUtils;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Text with Android's own engine: grapheme clusters and their advances
 * (with kerning, from Paint.getTextRunAdvances), and each cluster rasterized
 * into the shared RGBA atlas the first time it is drawn. Called on the GL
 * thread only.
 */
final class MBText {
    static final int ATLAS = 2048;

    static final class Entry {
        String text;
        float size;
        int weight;
        int style;  // 1 italic, 2 the code face
        boolean done;
        double u, v, w, h, ox, oy;
        int color;
    }

    static final HashMap<String, Integer> keys = new HashMap<>();
    static final ArrayList<Entry> entries = new ArrayList<>();
    static final HashMap<String, Paint> paints = new HashMap<>();
    static int packX, packY, packH, generation;
    static float[] adv = new float[1024];
    static final BreakIterator graphemes = BreakIterator.getCharacterInstance();

    static void reset() {
        for (Entry e : entries) e.done = false;
        packX = packY = packH = 0;
        generation++;
    }

    /** The face of style bits: 2 the monospaced (code) face, 4 the serif one (Noto Serif, its CJK for Han), else the system's. */
    static Typeface face(int style) {
        return (style & 2) != 0 ? Typeface.MONOSPACE : (style & 4) != 0 ? Typeface.SERIF : Typeface.DEFAULT;
    }

    static Paint paint(float size, int weight, int style) {
        String k = size + "/" + weight + "/" + style;
        Paint p = paints.get(k);
        if (p == null) {
            p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
            Typeface base = face(style);
            p.setTypeface(Typeface.create(base, weight, (style & 1) != 0));
            p.setTextSize(size);
            // ligatures as the system draws them: shape() tells MoonBit which clusters a ligature covers
            p.setColor(Color.WHITE);
            paints.put(k, p);
        }
        return p;
    }

    static int atlasGeneration() {
        return generation;
    }

    /** Pixels a point: text is measured at the size it is drawn in on the screen. */
    static float density() {
        return scale > 0 ? scale : Host.view != null ? Host.view.density : 1;
    }

    /** mbui-render's: the text at a draw list's scale, not the screen's (android_host.c mb_render_init_offscreen). */
    static float scale;

    static void setScale(float s) {
        scale = s;
        reset();
    }

    static void fontMetrics(double size, int weight, int style, double[] out) {
        float d = density();
        Paint.FontMetrics m = paint((float) size * d, weight, style).getFontMetrics();
        out[0] = -m.ascent / d;
        out[1] = m.descent / d;
        out[2] = Math.round(size * 1.42);
    }

    static int shape(String text, double size, int weight, int style, double[] out) {
        // measured in pixels, as the screen has them (at the size in points the font's hinting rounds each
        // advance to a whole point: a long word came out a few points wider than the system draws it)
        float d = density();
        Paint p = paint((float) size * d, weight, style);
        int n = text.length();
        if (adv.length < n) adv = new float[n * 2];
        char[] chars = text.toCharArray();
        // a run at a time in its own direction (shaped left to right, Arabic came out in letters that do not join,
        // wider than the system draws the word)
        if (Bidi.requiresBidi(chars, 0, n)) {
            Bidi b = new Bidi(chars, 0, null, 0, n, Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT);
            for (int r = 0; r < b.getRunCount(); r++) {
                int rs = b.getRunStart(r), rl = b.getRunLimit(r) - rs;
                p.getTextRunAdvances(chars, rs, rl, rs, rl, (b.getRunLevel(r) & 1) != 0, adv, rs);
            }
        } else {
            p.getTextRunAdvances(chars, 0, n, 0, n, false, adv, 0);
        }
        // tabs to the next stop, as android.text.Layout puts them (every 20 pixels from the line's start)
        float x = 0;
        for (int i = 0; i < n; i++) {
            if (chars[i] == '\t') adv[i] = (float) Math.floor((x + 20) / 20) * 20 - x;
            x += adv[i];
        }
        for (int i = 0; i < n; i++) adv[i] /= d;
        graphemes.setText(text);
        int cap = out.length / 4;
        int k = 0;
        int start = graphemes.first();
        for (int end = graphemes.next(); end != BreakIterator.DONE && k < cap;
                start = end, end = graphemes.next()) {
            double a = 0;
            for (int i = start; i < end; i++) a += adv[i];
            char c = chars[start];
            int key;
            if (c == '\n') {
                a = 0;
                key = -1;
            } else if (c == ' ' || c == '\t') {
                key = -1;
            } else if (a == 0 && k > 0 && out[(k - 1) * 4 + 3] != -1) {
                // no advance of its own: the shaper drew it as part of the glyph before it, a ligature ("fl"),
                // whose whole advance Paint puts on its first letter; MoonBit draws the ligature from that one
                // (drawn on its own, "flex" came out "f ɭex")
                key = -2;
            } else {
                key = intern(text.substring(start, end), (float) size, weight, style);
            }
            out[k * 4] = start;
            out[k * 4 + 1] = end - start;
            out[k * 4 + 2] = a;
            out[k * 4 + 3] = key;
            k++;
        }
        return k;
    }

    static int intern(String cluster, float size, int weight, int style) {
        String k = cluster + '\u0001' + size + '\u0001' + weight + '\u0001' + style;
        Integer id = keys.get(k);
        if (id != null) return id;
        Entry e = new Entry();
        e.text = cluster;
        e.size = size;
        e.weight = weight;
        e.style = style;
        entries.add(e);
        keys.put(k, entries.size() - 1);
        return entries.size() - 1;
    }

    /** The key of a piece of text drawn whole (a word of a joining script, a ligature). */
    static int textKey(String text, double size, int weight, int style) {
        return intern(text, (float) size, weight, style);
    }

    /**
     * Whether a cluster drawn in white came out in colours of its own (an emoji's, grey ones too): any pixel of some
     * opacity not white.
     */
    static boolean isColor(Bitmap b) {
        int w = b.getWidth(), h = b.getHeight();
        int[] px = new int[w * h];
        b.getPixels(px, 0, w, 0, 0, w, h);
        for (int v : px) {
            int a = v >>> 24, r = (v >> 16) & 255, g = (v >> 8) & 255, bl = v & 255;
            if (a > 64 && Math.min(r, Math.min(g, bl)) < 224) return true;
        }
        return false;
    }

    static void glyph(int key, double[] out) {
        if (key < 0 || key >= entries.size()) {
            for (int i = 0; i < 7; i++) out[i] = 0;
            return;
        }
        Entry e = entries.get(key);
        if (!e.done) rasterize(e);
        out[0] = e.u;
        out[1] = e.v;
        out[2] = e.w;
        out[3] = e.h;
        out[4] = e.ox;
        out[5] = e.oy;
        out[6] = e.color;
    }

    static void rasterize(Entry e) {
        e.done = true;
        e.w = 0;
        float sc = density();
        Paint p = paint(e.size * sc, e.weight, e.style);
        Rect b = new Rect();
        p.getTextBounds(e.text, 0, e.text.length(), b);
        int pad = 1;
        int pw = b.width() + 2 * pad, ph = b.height() + 2 * pad;
        if (b.width() <= 0 || b.height() <= 0 || pw > 512 || ph > 512) return;
        if (packX + pw + 1 > ATLAS) {
            packX = 0;
            packY += packH + 1;
            packH = 0;
        }
        if (packY + ph + 1 > ATLAS) {
            for (Entry x : entries) x.done = false;
            e.done = true;
            packX = packY = packH = 0;
            generation++;
        }
        Bitmap bmp = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        c.drawText(e.text, pad - b.left, pad - b.top, p);
        e.color = isColor(bmp) ? 1 : 0;
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, Native.atlasTexture());
        GLUtils.texSubImage2D(GLES30.GL_TEXTURE_2D, 0, packX, packY, bmp);
        bmp.recycle();
        e.u = packX;
        e.v = packY;
        e.w = pw / sc;
        e.h = ph / sc;
        e.ox = (b.left - pad) / sc;
        e.oy = (b.top - pad) / sc;
        packX += pw + 1;
        packH = Math.max(packH, ph);
    }

    // ---- the platform's own text drawing (textref_native.mbt, for src/textdiff) ----
    // A line drawn as an app's text is (StaticLayout, as Compose's Text and TextView draw it, with the default font
    // features) into a bitmap at the places mbui draws it; and the window's own picture, read back from GL right after
    // the next frame is drawn. PNGs in the app's files/textdiff.

    static Bitmap refBitmap;
    static Canvas refCanvas;
    static float refScale;
    static String frameName;

    static File refFile(String name) {
        File d = new File(Host.activity.getFilesDir(), "textdiff");
        d.mkdirs();
        return new File(d, name + ".png");
    }

    static boolean save(Bitmap b, String name) {
        try (FileOutputStream o = new FileOutputStream(refFile(name))) {
            return b.compress(Bitmap.CompressFormat.PNG, 100, o);
        } catch (Exception e) {
            Host.log("textdiff: " + name + ": " + e);
            return false;
        }
    }

    static void refBegin(double w, double h, double scale, int bg) {
        refScale = (float) scale;
        refBitmap = Bitmap.createBitmap((int) Math.round(w * scale), (int) Math.round(h * scale), Bitmap.Config.ARGB_8888);
        refCanvas = new Canvas(refBitmap);
        refCanvas.drawColor(0xFF000000 | bg);
    }

    static void refText(String text, double size, int weight, int style, double x, double base, int color, double[] out) {
        for (int i = 0; i < 5; i++) out[i] = 0;
        if (refCanvas == null) return;
        float d = refScale;
        TextPaint p = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        p.setTypeface(Typeface.create(face(style), weight, (style & 1) != 0));
        p.setTextSize((float) size * d);
        p.setColor(0xFF000000 | color);
        StaticLayout l = StaticLayout.Builder.obtain(text, 0, text.length(), p, 1 << 20)
                .setIncludePad(false).setAlignment(Layout.Alignment.ALIGN_NORMAL).build();
        // the line's left edge at x (a right-to-left paragraph is laid out against the right of its width)
        float left = l.getLineLeft(0);
        refCanvas.save();
        refCanvas.translate((float) x * d - left, (float) base * d - l.getLineBaseline(0));
        l.draw(refCanvas);
        refCanvas.restore();
        out[0] = l.getLineWidth(0) / d;
        Rect b = new Rect();
        p.getTextBounds(text, 0, text.length(), b);
        out[1] = b.left / d;
        out[2] = b.top / d;
        out[3] = b.right / d;
        out[4] = b.bottom / d;
    }

    static boolean refEnd(String name) {
        if (refBitmap == null) return false;
        boolean ok = save(refBitmap, name);
        refBitmap.recycle();
        refBitmap = null;
        refCanvas = null;
        return ok;
    }

    static boolean refFrame(String name) {
        frameName = name;
        return true;
    }

    /** After each frame is drawn, on the GL thread: the picture asked for (refFrame), before it is shown. */
    static void frameDrawn() {
        if (frameName == null) return;
        String name = frameName;
        frameName = null;
        int w = Host.view.getWidth(), h = Host.view.getHeight();
        ByteBuffer buf = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder());
        GLES30.glReadPixels(0, 0, w, h, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, buf);
        Bitmap up = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        up.copyPixelsFromBuffer(buf);
        // GL's rows go up from the bottom
        android.graphics.Matrix m = new android.graphics.Matrix();
        m.preScale(1, -1);
        Bitmap b = Bitmap.createBitmap(up, 0, 0, w, h, m, false);
        save(b, name);
        up.recycle();
        b.recycle();
    }
}
