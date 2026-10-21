package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * PDFs drawn by the system's PdfRenderer (src/host/host_native.mbt `pdf_*`), as still.fail's Android app draws them
 * (FilePreview.kt PdfViewer): the bytes put in a file of the app's cache (the renderer reads a file), the pages' sizes
 * read as it opens, each page drawn on white off the GL thread, one at a time (the renderer opens one page at a time),
 * and uploaded as an image of the host's table (Images.upload).
 */
final class Pdfs {
    static final class Doc {
        final File file;
        PdfRenderer renderer;
        int[] sizes = new int[0];  // width, height in points, page by page

        Doc(File file) {
            this.file = file;
        }
    }

    static final ConcurrentHashMap<Integer, Doc> docs = new ConcurrentHashMap<>();
    static final AtomicInteger next = new AtomicInteger();
    static final ExecutorService draw = Executors.newSingleThreadExecutor();

    static int open(byte[] data) {
        int id = next.incrementAndGet();
        File f = new File(Host.activity.getCacheDir(), "pdf-" + id + ".pdf");
        Doc d = new Doc(f);
        docs.put(id, d);
        try {
            try (FileOutputStream out = new FileOutputStream(f)) {
                out.write(data);
            }
            ParcelFileDescriptor fd = ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
            PdfRenderer r;
            try {
                r = new PdfRenderer(fd);
            } catch (IOException | RuntimeException e) {
                fd.close();
                throw e;
            }
            int n = r.getPageCount();
            int[] sizes = new int[n * 2];
            for (int i = 0; i < n; i++) {
                try (PdfRenderer.Page p = r.openPage(i)) {
                    sizes[i * 2] = p.getWidth();
                    sizes[i * 2 + 1] = p.getHeight();
                }
            }
            d.sizes = sizes;
            d.renderer = r;
            Host.log("pdf " + id + ": " + n + " pages, " + data.length + " bytes");
        } catch (IOException | RuntimeException e) {
            Host.log("pdf " + id + ": cannot open: " + e);
        }
        return id;
    }

    static int pages(int id) {
        Doc d = docs.get(id);
        return d == null || d.renderer == null ? -1 : d.sizes.length / 2;
    }

    static void pageSize(int id, int page, double[] out) {
        Doc d = docs.get(id);
        boolean in = d != null && page >= 0 && page * 2 + 1 < d.sizes.length;
        out[0] = in ? d.sizes[page * 2] : 0;
        out[1] = in ? d.sizes[page * 2 + 1] : 0;
    }

    /** Page `page` drawn at most `maxPx` on its longer side, into image `image` (made by the C side). */
    static void pageLoad(int id, int page, int maxPx, int image) {
        Doc d = docs.get(id);
        Runnable redo = () -> draw.execute(() -> render(d, id, page, maxPx, image));
        Images.live.put(image, new Images.Req("pdf:" + id + "/" + page, null, maxPx, redo));
        redo.run();
    }

    static void render(Doc d, int id, int page, int maxPx, int image) {
        Bitmap b = null;
        int pw = 0, ph = 0;
        if (d != null) {
            synchronized (d) {
                if (d.renderer != null && page >= 0 && page < d.sizes.length / 2) {
                    pw = d.sizes[page * 2];
                    ph = d.sizes[page * 2 + 1];
                    double k = maxPx / (double) Math.max(1, Math.max(pw, ph));
                    int w = Math.max(1, (int) Math.round(pw * k)), h = Math.max(1, (int) Math.round(ph * k));
                    try (PdfRenderer.Page p = d.renderer.openPage(page)) {
                        b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                        b.eraseColor(Color.WHITE);
                        p.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                    } catch (RuntimeException e) {
                        Host.log("pdf " + id + ": page " + page + ": " + e);
                        b = null;
                    }
                }
            }
        }
        Bitmap bmp = b;
        int ow = pw, oh = ph;
        Host.view.toGL(() -> Images.upload(image, bmp, ow, oh));
    }

    static void close(int id) {
        Doc d = docs.remove(id);
        if (d == null) return;
        draw.execute(() -> {
            synchronized (d) {
                if (d.renderer != null) d.renderer.close();
                d.renderer = null;
            }
            if (!d.file.delete()) Host.log("pdf " + id + ": its file stays in the cache");
        });
    }
}
