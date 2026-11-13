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
import android.os.Build;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;

/**
 * Text with Android's own engine: grapheme clusters and their advances
 * (with kerning, from Paint.getTextRunAdvances), and each cluster rasterized
 * as it is asked for, put where MoonBit says (its atlas.mbt: what goes where,
 * and what makes room) in an atlas: the words' (their cover, a byte a texel)
 * or colour glyphs' (RGBA). Called on the GL thread
 * only, but for the drawing ahead (ahead): the glyphs shaped and not drawn
 * yet, drawn on a thread of their own and taken when they are first asked
 * for; what was put in a frame uploaded once, a row of the atlas at a time,
 * before the frame is drawn (flush).
 */
final class MBText {
    static final class Entry {
        final String text;
        final float size;
        final int weight;
        final int style;  // 1 italic, 2 the code face
        // drawn ahead (under `lock`): NONE, ASKED (in `asked`), DRAWING (by the thread ahead), DRAWN (`drawn`); the
        // scale and the faces it is to be drawn at
        int ahead;
        Drawn drawn;
        float askScale;
        int askFaces;

        Entry(String text, float size, int weight, int style) {
            this.text = text;
            this.size = size;
            this.weight = weight;
            this.style = style;
        }
    }

    /** A cluster drawn in white, a pixel round its bounds (none: nothing to draw), at a scale, in the faces as they were. */
    static final class Drawn {
        Bitmap bmp;
        final Rect b = new Rect();
        int color;
        float scale;
        int faces;
    }

    /** A glyph put in an atlas this frame (colour glyphs' or the words'), its picture to be uploaded there (flush). */
    static final class Placed {
        final Bitmap bmp;
        final int x, y;
        final boolean colour;

        Placed(Bitmap bmp, int x, int y, boolean colour) {
            this.bmp = bmp;
            this.x = x;
            this.y = y;
            this.colour = colour;
        }
    }

    /** A colour glyph's place across is this far past its place in colour glyphs' atlas (android_host.c MB_ATLAS_COLOR_U). */
    static final int COLOUR_U = 16384;

    // each font's clusters (fontKey: its size, weight and style), their keys
    static final HashMap<Long, HashMap<String, Integer>> keys = new HashMap<>();
    static final ArrayList<Entry> entries = new ArrayList<>();
    static final HashMap<Long, Paint> paints = new HashMap<>();
    static final ArrayList<Placed> placed = new ArrayList<>();
    static int generation;
    // the glyph drawn last (glyph), its picture until it is put in its atlas (glyphPut), and whether it is in colours
    static int heldKey = -1;
    static Bitmap held;
    static boolean heldColour;
    // moves on as the faces change: what was drawn in them before is drawn again
    static int faces;
    static float[] adv = new float[1024];
    static char[] chars = new char[1024];
    static final BreakIterator graphemes = BreakIterator.getCharacterInstance();

    /** What was drawn before is gone (a new surface, its atlas empty; the faces or the scale changed): drawn again as it is asked for. */
    static void reset() {
        generation++;
        dropHeld();
        dropPlaced();
    }

    /** A font's key: its size's bits, its weight and its style. */
    static long fontKey(float size, int weight, int style) {
        return ((long) Float.floatToIntBits(size) << 32) | ((long) (weight & 0xFFFF) << 16) | (style & 0xFFFF);
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

    /** The typeface a style is drawn in at a weight: its face given, else the system's (face). (On either thread: the faces given are changed on the GL thread.) */
    static synchronized Typeface typeface(int style, int weight) {
        int f = faceId(style);
        Typeface given = f > 0 ? faceTypeface(f, weight, (style & 1) != 0) : null;
        return given != null ? given : Typeface.create(face(style), weight, (style & 1) != 0);
    }

    static synchronized boolean take(int f, Object src, int weight) {
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

    static synchronized void faceClear(int f) {
        if (f <= 0 || f >= FACES || !given(f)) return;
        faceFiles[f].clear();
        faceWeights[f].clear();
        facesChanged();
    }

    /** What was measured and drawn before a face changed: forgotten (MoonBit drops its glyphs as the generation moves on). */
    static void facesChanged() {
        paints.clear();
        faces++;
        reset();
    }

    static Paint paint(float size, int weight, int style) {
        return paintIn(paints, size, weight, style);
    }

    /** The paint of a font at a size in pixels, kept in `paints` (the GL thread's, or the thread ahead's). */
    static Paint paintIn(HashMap<Long, Paint> paints, float size, int weight, int style) {
        long k = fontKey(size, weight, style);
        Paint p = paints.get(k);
        if (p == null) {
            p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
            p.setTypeface(typeface(style, weight));
            p.setTextSize(size);
            // ligatures as the system draws them: shape() tells MoonBit which clusters a ligature covers; none for
            // words with letter spacing (style & 8), each cluster spaced on its own; digits all one width where
            // style & 32 (style.mbt style_tabular)
            String features = ((style & 8) != 0 ? "'liga' 0, 'clig' 0" : "")
                    + ((style & 8) != 0 && (style & 32) != 0 ? ", " : "")
                    + ((style & 32) != 0 ? "'tnum' 1" : "");
            if (!features.isEmpty()) p.setFontFeatureSettings(features);
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
        if (Build.VERSION.SDK_INT >= 34) {
            Paint.FontMetricsInt c = new Paint.FontMetricsInt();
            p.getFontMetricsInt(HAN, 0, HAN.length(), 0, HAN.length(), false, c);
            out[3] = -c.ascent / d;
            out[4] = c.descent / d;
        } else {
            // the text-run getFontMetricsInt is API 34's (below it: NoSuchMethodError, the app aborted as it started);
            // StaticLayout's fallback line spacing gives the taller of the two directly
            StaticLayout l = StaticLayout.Builder.obtain(HAN, 0, HAN.length(), new TextPaint(p), 1 << 20)
                    .setIncludePad(false).setUseLineSpacingFromFallbacks(true).build();
            out[3] = -l.getLineAscent(0) / d;
            out[4] = l.getLineDescent(0) / d;
        }
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
        if (MBText.chars.length < n) MBText.chars = new char[n * 2];
        char[] chars = MBText.chars;
        text.getChars(0, n, chars, 0);
        HashMap<String, Integer> font = clusters((float) size, weight, style);
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
                key = intern(font, text.substring(start, end), (float) size, weight, style);
            }
            out[k * 4] = start;
            out[k * 4 + 1] = end - start;
            out[k * 4 + 2] = a;
            out[k * 4 + 3] = key;
            k++;
        }
        return k;
    }

    /** A font's clusters and their keys. */
    static HashMap<String, Integer> clusters(float size, int weight, int style) {
        long k = fontKey(size, weight, style);
        HashMap<String, Integer> m = keys.get(k);
        if (m == null) {
            m = new HashMap<>();
            keys.put(k, m);
        }
        return m;
    }

    static int intern(HashMap<String, Integer> font, String cluster, float size, int weight, int style) {
        Integer id = font.get(cluster);
        if (id != null) return id;
        entries.add(new Entry(cluster, size, weight, style));
        font.put(cluster, entries.size() - 1);
        return entries.size() - 1;
    }

    /** The key of a piece of text drawn whole (a word of a joining script, a ligature). */
    static int textKey(String text, double size, int weight, int style) {
        return intern(clusters((float) size, weight, style), text, (float) size, weight, style);
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

    /**
     * Glyph `key` drawn (ahead, else here), its picture held for glyphPut: in `out` 0, 0 (where it goes is MoonBit's),
     * its size in points (0: nothing to draw), where its top left is from the pen, whether it is in colours of its own.
     */
    static void glyph(int key, double[] out) {
        for (int i = 0; i < 7; i++) out[i] = 0;
        dropHeld();
        if (key < 0 || key >= entries.size()) return;
        Entry e = entries.get(key);
        float sc = density();
        Drawn d = drawnAhead(e, sc);
        if (d == null) d = draw(e, sc, paint(e.size * sc, e.weight, e.style), faces);
        if (d.bmp == null) return;
        int pad = 1;
        heldKey = key;
        held = d.bmp;
        heldColour = d.color != 0;
        out[2] = d.bmp.getWidth() / sc;
        out[3] = d.bmp.getHeight() / sc;
        out[4] = (d.b.left - pad) / sc;
        out[5] = (d.b.top - pad) / sc;
        out[6] = d.color;
    }

    /**
     * The glyph drawn last put in its atlas, its top left at x, y (a colour glyph's COLOUR_U across past its place in
     * theirs): uploaded with the frame's others (flush).
     */
    static void glyphPut(int key, int x, int y) {
        boolean colour = x >= COLOUR_U;
        if (key != heldKey || held == null || colour != heldColour) return;
        placed.add(new Placed(held, colour ? x - COLOUR_U : x, y, colour));
        held = null;
        heldKey = -1;
    }

    /** The glyph drawn last, not put in the atlas, let go. */
    static void dropHeld() {
        if (held != null) held.recycle();
        held = null;
        heldKey = -1;
    }

    /** `e` drawn in white a pixel round its bounds, at `sc` pixels a point with `p` (its font at that size): on either thread. */
    static Drawn draw(Entry e, float sc, Paint p, int faces) {
        Drawn d = new Drawn();
        d.scale = sc;
        d.faces = faces;
        Rect b = d.b;
        p.getTextBounds(e.text, 0, e.text.length(), b);
        int pad = 1;
        int pw = b.width() + 2 * pad, ph = b.height() + 2 * pad;
        if (b.width() <= 0 || b.height() <= 0 || pw > 512 || ph > 512) return d;
        Bitmap bmp = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        c.drawText(e.text, pad - b.left, pad - b.top, p);
        d.color = isColor(bmp) ? 1 : 0;
        d.bmp = bmp;
        return d;
    }

    /**
     * The glyphs put since the last frame was drawn, into their atlases before this one is: those put one after
     * another on a shelf of one in one upload (side by side, a pixel apart, right of what the shelf had), not one each;
     * one put anywhere else (another shelf, another plot, the other atlas) starts another. The words' atlas takes a
     * glyph's cover alone (drawn in white: its alpha), a byte a texel. The texture bound on the unit active, as it was
     * bound for each glyph before.
     */
    static void flush() {
        int n = placed.size();
        if (n == 0) return;
        int bound = -1;
        int i = 0;
        while (i < n) {
            Placed first = placed.get(i);
            int j = i, right = first.x - 1, h = 0;
            while (j < n && placed.get(j).colour == first.colour && placed.get(j).y == first.y
                    && placed.get(j).x == right + 1) {
                Placed g = placed.get(j);
                right = g.x + g.bmp.getWidth();
                h = Math.max(h, g.bmp.getHeight());
                j++;
            }
            int tex = first.colour ? Native.colourAtlasTexture() : Native.atlasTexture();
            if (tex != bound) {
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, tex);
                bound = tex;
            }
            int w = right - first.x;
            if (first.colour) {
                if (j - i == 1) {
                    GLUtils.texSubImage2D(GLES30.GL_TEXTURE_2D, 0, first.x, first.y, first.bmp);
                } else {
                    Bitmap row = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                    Canvas c = new Canvas(row);
                    for (int k = i; k < j; k++) {
                        Placed g = placed.get(k);
                        c.drawBitmap(g.bmp, g.x - first.x, 0, null);
                    }
                    GLUtils.texSubImage2D(GLES30.GL_TEXTURE_2D, 0, first.x, first.y, row);
                    row.recycle();
                }
            } else {
                // each glyph's alpha where it lies in the row, nothing (0) round it
                if (cover == null || cover.capacity() < w * h) {
                    cover = ByteBuffer.allocateDirect(Math.max(w * h, 1 << 16)).order(ByteOrder.nativeOrder());
                }
                cover.clear();
                for (int b = 0; b < w * h; b++) cover.put(b, (byte) 0);
                for (int k = i; k < j; k++) {
                    Placed g = placed.get(k);
                    int gw = g.bmp.getWidth(), gh = g.bmp.getHeight();
                    if (px.length < gw * gh) px = new int[gw * gh * 2];
                    g.bmp.getPixels(px, 0, gw, 0, 0, gw, gh);
                    int ox = g.x - first.x;
                    for (int y = 0; y < gh; y++)
                        for (int x = 0; x < gw; x++) cover.put(y * w + ox + x, (byte) (px[y * gw + x] >>> 24));
                }
                GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1);
                cover.position(0);
                GLES30.glTexSubImage2D(GLES30.GL_TEXTURE_2D, 0, first.x, first.y, w, h, GLES30.GL_RED,
                        GLES30.GL_UNSIGNED_BYTE, cover);
                GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 4);
            }
            for (int k = i; k < j; k++) placed.get(k).bmp.recycle();
            i = j;
        }
        placed.clear();
    }

    /** A glyph's pixels as they are read (flush), and a row's cover as it is uploaded: kept from one to the next. */
    static int[] px = new int[4096];
    static ByteBuffer cover;

    /** What was put and not uploaded, let go: the atlas is gone (reset). */
    static void dropPlaced() {
        for (Placed g : placed) g.bmp.recycle();
        placed.clear();
    }

    // ---- drawing ahead: the glyphs shaped and not drawn yet (text.mbt glyphs_ahead), on a thread of their own ----

    static final int NONE = 0, ASKED = 1, DRAWING = 2, DRAWN = 3;
    /** The most glyphs asked for or drawn ahead and not placed yet (the oldest drawn let go past it). */
    static final int AHEAD_MOST = 1024;
    static final Object lock = new Object();
    // under lock: what the thread ahead is to draw, in the order asked; what it drew and is not placed yet, oldest first
    static final ArrayDeque<Entry> asked = new ArrayDeque<>();
    static final LinkedHashSet<Entry> drawnAhead = new LinkedHashSet<>();
    static int aheadCount;
    static Thread aheadThread;

    /** The glyphs of keys[0..n) to draw ahead, at the scale and in the faces of now. GL thread. */
    static void ahead(int[] ks, int n) {
        float sc = density();
        boolean any = false;
        synchronized (lock) {
            for (int i = 0; i < n; i++) {
                int k = ks[i];
                if (k < 0 || k >= entries.size()) continue;
                Entry e = entries.get(k);
                if (e.ahead != NONE) continue;
                if (aheadCount >= AHEAD_MOST && !dropOldestDrawn()) break;
                e.ahead = ASKED;
                e.askScale = sc;
                e.askFaces = faces;
                asked.add(e);
                aheadCount++;
                any = true;
            }
            if (any) lock.notifyAll();
        }
        if (any && aheadThread == null) {
            aheadThread = new Thread(MBText::drawAhead, "mbui glyphs");
            aheadThread.setDaemon(true);
            aheadThread.start();
        }
    }

    /** The oldest glyph drawn ahead and not placed, let go (under lock): false when there is none. */
    static boolean dropOldestDrawn() {
        java.util.Iterator<Entry> it = drawnAhead.iterator();
        if (!it.hasNext()) return false;
        Entry e = it.next();
        it.remove();
        if (e.drawn != null && e.drawn.bmp != null) e.drawn.bmp.recycle();
        e.drawn = null;
        e.ahead = NONE;
        aheadCount--;
        return true;
    }

    /**
     * What was drawn ahead of `e` at `sc` in the faces of now, taken; null when it was not (asked and not begun: no
     * longer asked, drawn here). While the thread ahead draws it, waited for. GL thread.
     */
    static Drawn drawnAhead(Entry e, float sc) {
        synchronized (lock) {
            if (e.ahead == NONE) return null;
            if (e.ahead == ASKED) {
                // (left in `asked`: the thread ahead passes over it)
                e.ahead = NONE;
                aheadCount--;
                return null;
            }
            while (e.ahead == DRAWING) {
                try {
                    lock.wait();
                } catch (InterruptedException x) {
                    Thread.currentThread().interrupt();
                    return null;
                }
            }
            if (e.ahead != DRAWN) return null;
            Drawn d = e.drawn;
            e.drawn = null;
            e.ahead = NONE;
            aheadCount--;
            drawnAhead.remove(e);
            if (d.scale != sc || d.faces != faces) {
                if (d.bmp != null) d.bmp.recycle();
                return null;
            }
            return d;
        }
    }

    /** The thread ahead: each glyph asked for drawn with its own paints, as the GL thread would draw it. */
    static void drawAhead() {
        HashMap<Long, Paint> mine = new HashMap<>();
        int mineFaces = -1;
        while (true) {
            Entry e;
            float sc;
            int f;
            synchronized (lock) {
                while (asked.isEmpty()) {
                    try {
                        lock.wait();
                    } catch (InterruptedException x) {
                        return;
                    }
                }
                e = asked.poll();
                if (e.ahead != ASKED) continue;
                e.ahead = DRAWING;
                sc = e.askScale;
                f = e.askFaces;
            }
            Drawn d = null;
            try {
                if (f != mineFaces) {
                    mine.clear();
                    mineFaces = f;
                }
                d = draw(e, sc, paintIn(mine, e.size * sc, e.weight, e.style), f);
            } catch (Throwable x) {
                // (out of memory for its picture, as much as anything: let be, drawn on the GL thread when it is asked
                // for; never left DRAWING for that thread to wait on)
                Host.log("glyph ahead: " + x);
            }
            synchronized (lock) {
                if (d == null) {
                    e.ahead = NONE;
                    aheadCount--;
                } else {
                    e.drawn = d;
                    e.ahead = DRAWN;
                    drawnAhead.add(e);
                }
                lock.notifyAll();
            }
        }
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
