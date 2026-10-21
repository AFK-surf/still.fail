package dev.mbui;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * A small HTTP listener on a loopback address, Android's twin of src/host/apple_listen.m (listen_api.h): a login's
 * browser coming back to http://127.0.0.1:&lt;port&gt;/… Two users, as on Apple's systems: an app's own sign-in in the
 * browser ({@link BrowserLogin}, mbui/host {@code browser_login}) and the still.fail core's {@code listen.*}
 * ({@link CoreHost}: taking a station's login callback on this device, {@code canRelay}).
 *
 * <p>Each request is read whole (head up to 64 KB, body up to 1 MB, 15 s at most, as ember's Loopback.kt) and handed on
 * once; it is answered once with {@link #respond}, which closes its connection. A request nobody answers waits until
 * the listener closes. While any listener is open the app holds itself up with {@link LoginService} (a frozen process
 * answers nobody).
 */
final class Loopback {
    /** What a listener says: a request, or (request null) that it has closed and nothing more comes. */
    interface Taker {
        void took(Asked request);
    }

    /** A request that came: as the browser sent it (its path with its query, its headers in their order). */
    static final class Asked {
        final long request;
        final String method, path;
        final List<String[]> headers;
        final byte[] body;

        Asked(long request, String method, String path, List<String[]> headers, byte[] body) {
            this.request = request;
            this.method = method;
            this.path = path;
            this.headers = headers;
            this.body = body;
        }

        String header(String name) {
            for (String[] h : headers) if (h[0].equalsIgnoreCase(name)) return h[1];
            return "";
        }

        /** {request, method, path, headers: [[name, value]]}, as listen.next answers. */
        String json() {
            StringBuilder s = new StringBuilder("{\"request\":").append(request)
                    .append(",\"method\":").append(quote(method)).append(",\"path\":").append(quote(path))
                    .append(",\"headers\":[");
            for (int i = 0; i < headers.size(); i++) {
                if (i > 0) s.append(',');
                s.append('[').append(quote(headers.get(i)[0])).append(',').append(quote(headers.get(i)[1])).append(']');
            }
            return s.append("]}").toString();
        }
    }

    private static final class Server {
        final int id, port;
        final ServerSocket socket;
        final Taker taker;
        /** The connections whose request was handed on, by its number, until answered. */
        final Map<Long, Socket> asked = new ConcurrentHashMap<>();
        final AtomicLong next = new AtomicLong(1);
        volatile boolean closed;

        Server(int id, ServerSocket socket, Taker taker) {
            this.id = id;
            this.socket = socket;
            this.port = socket.getLocalPort();
            this.taker = taker;
        }
    }

    private static final Map<Integer, Server> servers = new ConcurrentHashMap<>();
    private static final AtomicInteger ids = new AtomicInteger(1);

    /** Most of a request's head and body taken (a login's callback: a query, or a small form). */
    private static final int HEAD_MOST = 64 * 1024, BODY_MOST = 1_000_000;
    /** A browser sends its request at once: one that has not in this long is let go. */
    private static final int READ_MS = 15_000;

    private Loopback() {}

    /**
     * Listens on {@code host} (127.0.0.1 or ::1, nothing else) at {@code port} (0: one the system picks): the
     * listener's id; its port is {@link #port}. Throws when it cannot (the port taken: "Address already in use").
     */
    static int open(String host, int port, Taker taker) throws IOException {
        InetAddress address;
        if (host.equals("127.0.0.1")) address = InetAddress.getByAddress("localhost", new byte[] {127, 0, 0, 1});
        else if (host.equals("::1")) {
            byte[] six = new byte[16];
            six[15] = 1;
            address = InetAddress.getByAddress("localhost", six);
        } else throw new IllegalArgumentException("not a loopback address: " + host);
        if (port < 0 || port > 65535) throw new IllegalArgumentException("no such port: " + port);
        ServerSocket socket = new ServerSocket();
        try {
            socket.bind(new InetSocketAddress(address, port), 16);
        } catch (IOException e) {
            socket.close();
            throw e;
        }
        Server server = new Server(ids.getAndIncrement(), socket, taker);
        servers.put(server.id, server);
        LoginService.listening(servers.size());
        Thread accept = new Thread(() -> {
            while (true) {
                Socket c;
                try {
                    c = socket.accept();
                } catch (IOException e) {
                    break;
                }
                Thread t = new Thread(() -> take(server, c), "mbui-loopback-" + server.port + "-request");
                t.setDaemon(true);
                t.start();
            }
            ended(server);
        }, "mbui-loopback-" + server.port);
        accept.setDaemon(true);
        accept.start();
        return server.id;
    }

    /** The port listener {@code id} listens at (0: none such). */
    static int port(int id) {
        Server s = servers.get(id);
        return s != null ? s.port : 0;
    }

    /** Answers request {@code request} of listener {@code id}, then closes its connection; nothing when it is gone. */
    static void respond(int id, long request, int status, List<String[]> headers, byte[] body) {
        Server s = servers.get(id);
        Socket c = s != null ? s.asked.remove(request) : null;
        if (c == null) return;
        try (Socket sock = c) {
            StringBuilder head = new StringBuilder("HTTP/1.1 ").append(status).append(' ').append(reason(status)).append("\r\n");
            for (String[] h : headers) {
                String k = h[0].toLowerCase(Locale.ROOT);
                // the connection's, not the answer's: each answer closes its connection
                if (k.equals("connection") || k.equals("transfer-encoding") || k.equals("content-length") || k.equals("keep-alive")) continue;
                head.append(h[0]).append(": ").append(h[1].replace("\r", "").replace("\n", "")).append("\r\n");
            }
            byte[] b = body != null ? body : new byte[0];
            head.append("Connection: close\r\nContent-Length: ").append(b.length).append("\r\n\r\n");
            OutputStream out = sock.getOutputStream();
            out.write(head.toString().getBytes(StandardCharsets.UTF_8));
            out.write(b);
            out.flush();
        } catch (IOException e) {
            // the browser went away: nothing to answer
        }
    }

    /** Stops listening: what is unanswered is closed unanswered, and the taker is told (once). Any thread. */
    static void close(int id) {
        Server s = servers.get(id);
        if (s == null) return;
        try {
            s.socket.close();  // the accept loop ends, and says so (ended)
        } catch (IOException e) {
            ended(s);
        }
    }

    private static void ended(Server s) {
        synchronized (s) {
            if (s.closed) return;
            s.closed = true;
        }
        servers.remove(s.id, s);
        for (Socket c : s.asked.values()) {
            try {
                c.close();
            } catch (IOException ignored) {
            }
        }
        s.asked.clear();
        LoginService.listening(servers.size());
        s.taker.took(null);
    }

    /** A connection's request read whole and handed on; one that is not HTTP, or too slow, closed. */
    private static void take(Server server, Socket c) {
        Asked asked = null;
        try {
            c.setSoTimeout(READ_MS);
            asked = read(server.next.getAndIncrement(), new BufferedInputStream(c.getInputStream()));
        } catch (IOException ignored) {
        }
        if (asked == null || server.closed) {
            try {
                c.close();
            } catch (IOException ignored) {
            }
            return;
        }
        server.asked.put(asked.request, c);
        server.taker.took(asked);
    }

    /** An HTTP/1.x request off a connection (numbered {@code n}): null for what is not one. */
    private static Asked read(long n, InputStream in) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        int last = 0;  // the last four bytes read: the head ends at CR LF CR LF
        while (last != 0x0d0a0d0a) {
            int b = in.read();
            if (b < 0 || head.size() >= HEAD_MOST) return null;
            head.write(b);
            last = (last << 8) | b;
        }
        String[] lines = head.toString("ISO-8859-1").split("\r\n");
        if (lines.length == 0) return null;
        String[] first = lines[0].split(" ");
        if (first.length != 3 || !first[2].startsWith("HTTP/1.")) return null;
        List<String[]> headers = new ArrayList<>();
        long length = 0;
        for (int i = 1; i < lines.length; i++) {
            int at = lines[i].indexOf(':');
            if (at <= 0) continue;
            String k = lines[i].substring(0, at).trim(), v = lines[i].substring(at + 1).trim();
            headers.add(new String[] {k, v});
            if (k.equalsIgnoreCase("content-length")) {
                try {
                    length = Long.parseLong(v);
                } catch (NumberFormatException e) {
                    return null;
                }
            }
        }
        if (length < 0) return null;
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        for (long left = length; left > 0; ) {
            int got = in.read(buf, 0, (int) Math.min(buf.length, left));
            if (got < 0) return null;
            if (body.size() < BODY_MOST) body.write(buf, 0, Math.min(got, BODY_MOST - body.size()));
            left -= got;
        }
        return new Asked(n, first[0], first[1], headers, body.toByteArray());
    }

    private static String reason(int status) {
        switch (status) {
            case 200: return "OK";
            case 302: return "Found";
            case 303: return "See Other";
            case 400: return "Bad Request";
            case 404: return "Not Found";
            case 502: return "Bad Gateway";
            default: return "Status";
        }
    }

    /** A JSON string (headers come as ISO-8859-1, so any char may be in them). */
    static String quote(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == '"' || ch == '\\') b.append('\\').append(ch);
            else if (ch < 0x20) b.append(String.format("\\u%04x", (int) ch));
            else b.append(ch);
        }
        return b.append('"').toString();
    }
}
