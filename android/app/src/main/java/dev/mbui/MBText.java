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

    /** The faces given (faceAdd, style.mbt): each a list of font files (a File, or a direct ByteBuffer of one) and the weight each is for (0: variable). */
    static final int FACES = 16;
    @SuppressWarnings("unchecked")
    static final ArrayList<Object>[] faceFiles = new ArrayList[FACES];
    @SuppressWarnings("unchecked")
    static final ArrayList<Integer>[] faceWeights = new ArrayList[FACES];

    /** The face a style is set in: the one it names; else code's, what people wrote's, the app's words' (not the serif face's); 0 none. */
    static int faceId(int style) {
        int f = (style >> 8) & 15;
        if (f > 0) return given(f) ? f : 0;
        if ((style & 2) != 0) return given(3) ? 3 : 0;
        if ((style & 16) != 0 && given(2)) return 2;
        if ((style & 4) != 0) return 0;
        return given(1) ? 1 : 0;
    }

    static boolean given(int f) {
        return faceFiles[f] != null && !faceFiles[f].isEmpty();
    }

    /** A font of a file or its bytes at a weight and slant (a variable one at the weight itself). */
    static android.graphics.fonts.Font font(Object src, int weight, int fileWeight, boolean italic) throws java.io.IOException {
        android.graphics.fonts.Font.Builder b = src instanceof File
            ? new android.graphics.fonts.Font.Builder((File) src)
            : new android.graphics.fonts.Font.Builder(((ByteBuffer) src).duplicate());
        if (fileWeight == 0) b.setFontVariationSettings("'wght' " + weight);
        return b.setWeight(fileWeight == 0 ? weight : fileWeight)
            .setSlant(italic ? android.graphics.fonts.FontStyle.FONT_SLANT_ITALIC : android.graphics.fonts.FontStyle.FONT_SLANT_UPRIGHT)
            .build();
    }

    /** Face `f` at a weight: its file for the nearest weight; what it lacks (Han, emoji) in the system's (null: unreadable). */
    static Typeface faceTypeface(int f, int weight, boolean italic) {
        int best = 0, bestd = Integer.MAX_VALUE;
        for (int i = 0; i < faceWeights[f].size(); i++) {
            int w = faceWeights[f].get(i);
            int d = w == 0 ? 0 : Math.abs(w - weight);
            if (d < bestd) {
                bestd = d;
                best = i;
            }
        }
        try {
            android.graphics.fonts.Font font = font(faceFiles[f].get(best), weight, faceWeights[f].get(best), italic);
            android.graphics.fonts.FontFamily fam = new android.graphics.fonts.FontFamily.Builder(font).build();
            return new Typeface.CustomFallbackBuilder(fam)
                .setStyle(new android.graphics.fonts.FontStyle(weight, italic ? android.graphics.fonts.FontStyle.FONT_SLANT_ITALIC : android.graphics.fonts.FontStyle.FONT_SLANT_UPRIGHT))
                .setSystemFallback((f == 3) ? "monospace" : "sans-serif")
                .build();
        } catch (Exception e) {
            return null;
        }
    }

    /** The typeface a style is drawn in at a weight: its face given, else the system's (face). */
    static Typeface typeface(int style, int weight) {
        int f = faceId(style);
        Typeface given = f > 0 ? faceTypeface(f, weight, (style & 1) != 0) : null;
        return given != null ? given : Typeface.create(face(style), weight, (style & 1) != 0);
    }

    static boolean take(int f, Object src, int weight) {
        if (f <= 0 || f >= FACES) return false;
        // one Android can read as a font, or none taken
        try {
            font(src, weight == 0 ? 400 : weight, weight, false);
        } catch (Exception e) {
            return false;
        }
        if (faceFiles[f] == null) {
            faceFiles[f] = new ArrayList<>();
            faceWeights[f] = new ArrayList<>();
        }
        faceFiles[f].add(src);
        faceWeights[f].add(weight);
        facesChanged();
        return true;
    }

    static boolean faceAdd(int f, String path, int weight) {
        return take(f, new File(path), weight);
    }

    static boolean faceAddBytes(int f, byte[] data, int weight) {
        ByteBuffer b = ByteBuffer.allocateDirect(data.length);
        b.put(data);
        b.flip();
        return take(f, b, weight);
    }

    static void faceClear(int f) {
        if (f <= 0 || f >= FACES || !given(f)) return;
        faceFiles[f].clear();
        faceWeights[f].clear();
        facesChanged();
    }

    /** What was measured and drawn before a face changed: forgotten (MoonBit drops its glyphs as the generation moves on). */
    static void facesChanged() {
        paints.clear();
        reset();
    }

    static Paint paint(float size, int weight, int style) {
        String k = size + "/" + weight + "/" + style;
        Paint p = paints.get(k);
        if (p == null) {
            p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
            p.setTypeface(typeface(style, weight));
            p.setTextSize(size);
            // ligatures as the system draws them: shape() tells MoonBit which clusters a ligature covers; none for
            // words with letter spacing (style & 8), each cluster spaced on its own
            if ((style & 8) != 0) p.setFontFeatureSettings("'liga' 0, 'clig' 0");
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

    /** A Han ideograph: what the font Chinese words fall back to is measured by. */
    private static final String HAN = "国";

    static void fontMetrics(double size, int weight, int style, double[] out) {
        // in whole pixels, as android.text.StaticLayout (and so Compose) sets a line by them
        float d = density();
        Paint p = paint((float) size * d, weight, style);
        Paint.FontMetricsInt m = p.getFontMetricsInt();
        out[0] = -m.ascent / d;
        out[1] = m.descent / d;
        out[2] = Math.round(size * 1.42);
        // the font a Han ideograph is drawn in (Noto Sans CJK, taller than the Latin face): a line with Chinese in it is
        // measured by the taller of the two, as StaticLayout's fallback line spacing does
        Paint.FontMetricsInt c = new Paint.FontMetricsInt();
        p.getFontMetricsInt(HAN, 0, HAN.length(), 0, HAN.length(), false, c);
        out[3] = -c.ascent / d;
        out[4] = c.descent / d;
        // lines set on whole pixels, as StaticLayout sets them
        out[5] = 1;
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
        p.setTypeface(typeface(style, weight));
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
