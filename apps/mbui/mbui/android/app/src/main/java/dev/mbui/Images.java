package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.opengl.GLES30;
import android.opengl.GLUtils;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Images: read and decoded on a few background threads straight to the size
 * asked for, EXIF orientation applied, then uploaded on the GL thread as
 * premultiplied RGBA textures the C renderer draws. A content:// source (a
 * photo of the gallery: Gallery.java) is the system's thumbnail of it.
 */
final class Images {
    // a few at a time, so a grid scrolled fast doesn't keep every core busy
    // with pictures already off screen
    static final ExecutorService pool = Executors.newFixedThreadPool(3);

    static final class Req {
        final String src;
        final byte[] data;
        final int maxPx;
        /** How to make it again if not by decoding (a PDF's page, Pdfs.java). */
        final Runnable redo;

        Req(String src, byte[] data, int maxPx) {
            this(src, data, maxPx, null);
        }

        Req(String src, byte[] data, int maxPx, Runnable redo) {
            this.src = src;
            this.data = data;
            this.maxPx = maxPx;
            this.redo = redo;
        }
    }

    // what each live image was loaded from, to decode it again if the GL
    // context (and with it every texture) is lost; GL thread only
    static final HashMap<Integer, Req> live = new HashMap<>();

    static void load(int id, String src, byte[] data, int maxPx) {
        Req r = new Req(src, data, maxPx);
        live.put(id, r);
        pool.execute(() -> decode(id, r));
    }

    // mbui-render (android_host.c mb_render_init_offscreen): its main holds the GL thread while it waits for its
    // images, so their uploads are kept here and done when it asks (pump), on that thread
    static volatile boolean held;
    static final ConcurrentLinkedQueue<Runnable> heldUploads = new ConcurrentLinkedQueue<>();

    static void hold() {
        held = true;
    }

    static void pump() {
        for (Runnable r; (r = heldUploads.poll()) != null; ) r.run();
    }

    static void toGL(Runnable r) {
        if (held) heldUploads.add(r);
        else Host.view.toGL(r);
    }

    static void free(int id) {
        live.remove(id);
    }

    static void reload() {
        for (Map.Entry<Integer, Req> e : live.entrySet()) {
            int id = e.getKey();
            Req r = e.getValue();
            if (r.redo != null) r.redo.run();
            else pool.execute(() -> decode(id, r));
        }
    }

    static void decode(int id, Req r) {
        long t0 = System.nanoTime();
        int[] orig = new int[2];
        Bitmap b = null;
        try {
            byte[] data = r.data;
            if (data == null && r.src.startsWith("content://")) {
                // a photo of the gallery (Gallery.java): its thumbnail, as big as asked for
                Bitmap t = Host.activity.getContentResolver().loadThumbnail(android.net.Uri.parse(r.src),
                        new android.util.Size(r.maxPx, r.maxPx), null);
                orig[0] = t.getWidth();
                orig[1] = t.getHeight();
                b = t.getConfig() == Bitmap.Config.ARGB_8888 ? t : t.copy(Bitmap.Config.ARGB_8888, false);
                if (b != t) t.recycle();
                Bitmap bmp = b;
                toGL(() -> upload(id, bmp, orig[0], orig[1]));
                return;
            }
            if (data == null && (r.src.startsWith("http://") || r.src.startsWith("https://"))) {
                data = fetch(r.src);
            }
            String path = r.src.startsWith("file://") ? r.src.substring(7) : r.src;
            try {
                // minSdk is 29, so ImageDecoder is always there; BitmapFactory
                // is the second try for what it can't read
                b = ImageDecoder.decodeBitmap(data != null
                        ? ImageDecoder.createSource(ByteBuffer.wrap(data))
                        : ImageDecoder.createSource(new File(path)),
                        (d, info, s) -> {
                            int w = info.getSize().getWidth(), h = info.getSize().getHeight();
                            orig[0] = w;
                            orig[1] = h;
                            double k = Math.min(1.0, r.maxPx / (double) Math.max(w, h));
                            if (k < 1) {
                                d.setTargetSize(Math.max(1, (int) Math.round(w * k)),
                                        Math.max(1, (int) Math.round(h * k)));
                            }
                            d.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                            d.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB));
                        });
            } catch (IOException e) {
                b = withFactory(data, path, r.maxPx, orig);
                if (b == null) throw e;
            }
            if (b.getConfig() != Bitmap.Config.ARGB_8888) {
                Bitmap c = b.copy(Bitmap.Config.ARGB_8888, false);
                b.recycle();
                b = c;
            }
        } catch (Throwable e) {
            Host.log("image " + r.src + ": " + e);
            b = null;
        }
        if (Host.bench != 0 && b != null) {
            Host.log("image " + orig[0] + "x" + orig[1] + " -> " + b.getWidth() + "x" + b.getHeight()
                    + " in " + (System.nanoTime() - t0) / 1000000 + " ms: " + r.src);
        }
        Bitmap bmp = b;
        toGL(() -> upload(id, bmp, orig[0], orig[1]));
    }

    /** Older decoders: a power-of-two subsample, then scaled and turned. */
    static Bitmap withFactory(byte[] data, String path, int maxPx, int[] orig) throws IOException {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        if (data != null) BitmapFactory.decodeByteArray(data, 0, data.length, o);
        else BitmapFactory.decodeFile(path, o);
        int w = o.outWidth, h = o.outHeight;
        if (w <= 0 || h <= 0) return null;
        o.inJustDecodeBounds = false;
        o.inSampleSize = 1;
        while (Math.max(w, h) / (o.inSampleSize * 2) >= maxPx) o.inSampleSize *= 2;
        Bitmap b = data != null ? BitmapFactory.decodeByteArray(data, 0, data.length, o)
                : BitmapFactory.decodeFile(path, o);
        if (b == null) return null;
        ExifInterface ex = data != null ? new ExifInterface(new ByteArrayInputStream(data))
                : new ExifInterface(path);
        int turn = ex.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        float k = (float) Math.min(1.0, maxPx / (double) Math.max(b.getWidth(), b.getHeight()));
        Matrix m = new Matrix();
        m.setScale(k, k);
        switch (turn) {
            case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_180: m.postRotate(180); break;
            case ExifInterface.ORIENTATION_FLIP_VERTICAL: m.postScale(1, -1); break;
            case ExifInterface.ORIENTATION_TRANSPOSE: m.postRotate(90); m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_90: m.postRotate(90); break;
            case ExifInterface.ORIENTATION_TRANSVERSE: m.postRotate(-90); m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_270: m.postRotate(-90); break;
        }
        boolean swap = turn >= ExifInterface.ORIENTATION_TRANSPOSE;
        orig[0] = swap ? h : w;
        orig[1] = swap ? w : h;
        if (m.isIdentity()) return b;
        Bitmap t = Bitmap.createBitmap(b, 0, 0, b.getWidth(), b.getHeight(), m, true);
        if (t != b) b.recycle();
        return t;
    }

    static byte[] fetch(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try (InputStream in = c.getInputStream()) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[64 * 1024];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toByteArray();
        } finally {
            c.disconnect();
        }
    }

    // ---- GL thread ----

    static void upload(int id, Bitmap b, int ow, int oh) {
        if (!live.containsKey(id)) {  // freed meanwhile
            if (b != null) b.recycle();
            return;
        }
        int[] t = {0};
        if (b != null) {
            GLES30.glGenTextures(1, t, 0);
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t[0]);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
            // Bitmaps are premultiplied, and uploaded as they are
            GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, b, 0);
        }
        Native.imageDone(id, t[0], b != null ? b.getWidth() : 0, b != null ? b.getHeight() : 0, ow, oh);
        if (b != null) b.recycle();
    }
}
