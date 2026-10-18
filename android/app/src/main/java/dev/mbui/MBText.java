package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.icu.text.BreakIterator;
import android.opengl.GLES30;
import android.opengl.GLUtils;

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

    static Paint paint(float size, int weight) {
        String k = size + "/" + weight;
        Paint p = paints.get(k);
        if (p == null) {
            p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
            p.setTypeface(Typeface.create(Typeface.DEFAULT, weight, false));
            p.setTextSize(size);
            p.setColor(Color.WHITE);
            paints.put(k, p);
        }
        return p;
    }

    static int atlasGeneration() {
        return generation;
    }

    static void fontMetrics(double size, int weight, double[] out) {
        Paint.FontMetrics m = paint((float) size, weight).getFontMetrics();
        out[0] = -m.ascent;
        out[1] = m.descent;
        out[2] = Math.round(size * 1.42);
    }

    static int shape(String text, double size, int weight, double[] out) {
        Paint p = paint((float) size, weight);
        int n = text.length();
        if (adv.length < n) adv = new float[n * 2];
        char[] chars = text.toCharArray();
        p.getTextRunAdvances(chars, 0, n, 0, n, false, adv, 0);
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
            } else {
                key = intern(text.substring(start, end), (float) size, weight);
            }
            out[k * 4] = start;
            out[k * 4 + 1] = end - start;
            out[k * 4 + 2] = a;
            out[k * 4 + 3] = key;
            k++;
        }
        return k;
    }

    static int intern(String cluster, float size, int weight) {
        String k = cluster + '\u0001' + size + '\u0001' + weight;
        Integer id = keys.get(k);
        if (id != null) return id;
        Entry e = new Entry();
        e.text = cluster;
        e.size = size;
        e.weight = weight;
        entries.add(e);
        keys.put(k, entries.size() - 1);
        return entries.size() - 1;
    }

    static boolean isColor(String s) {
        int cp = s.codePointAt(0);
        return cp >= 0x1F000 || (cp >= 0x2600 && cp < 0x27C0) || s.indexOf('️') >= 0;
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
        float sc = Host.view.density;
        Paint p = paint(e.size * sc, e.weight);
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
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, Native.atlasTexture());
        GLUtils.texSubImage2D(GLES30.GL_TEXTURE_2D, 0, packX, packY, bmp);
        bmp.recycle();
        e.u = packX;
        e.v = packY;
        e.w = pw / sc;
        e.h = ph / sc;
        e.ox = (b.left - pad) / sc;
        e.oy = (b.top - pad) / sc;
        e.color = isColor(e.text) ? 1 : 0;
        packX += pw + 1;
        packH = Math.max(packH, ph);
    }
}
