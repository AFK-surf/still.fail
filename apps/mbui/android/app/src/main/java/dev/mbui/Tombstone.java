package dev.mbui;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A native crash's tombstone as the system hands it (ApplicationExitInfo.getTraceInputStream on Android 12+), as
 * still.fail's Android app reads it (Tombstone.kt): the protobuf of AOSP's system/core/debuggerd/proto/tombstone.proto,
 * read here into the text a tombstone file has, the crashing thread first and the process's last log lines after. Only
 * the fields used are read; what cannot be read (an older format, a cut-off stream) falls back to the printable
 * strings in it.
 */
final class Tombstone {
    private Tombstone() {}

    private static final class Frame {
        long pc, offset;
        String function = "", file = "";
    }

    private static final class Thread {
        int id;
        String name = "";
        final List<Frame> frames = new ArrayList<>();
    }

    private static final class Log {
        String time = "", tag = "", message = "";
        int pid, tid, priority;
    }

    /** The tombstone as text, at most Crashes.LOGS long. */
    static String text(byte[] bytes) {
        String s;
        try {
            s = read(bytes);
        } catch (Exception e) {
            s = null;
        }
        if (s == null) s = strings(bytes);
        return Crashes.take(s, Crashes.LOGS);
    }

    /** The line a report is titled with: the abort message, or the signal. */
    static String headline(String text) {
        for (String l : text.split("\n", -1)) {
            if (l.startsWith("Abort message: ")) {
                String m = l.substring("Abort message: ".length());
                int a = 0, b = m.length();
                while (a < b && m.charAt(a) == '\'') a++;
                while (b > a && m.charAt(b - 1) == '\'') b--;
                return m.substring(a, b);
            }
        }
        for (String l : text.split("\n", -1)) if (l.startsWith("signal ")) return l;
        return null;
    }

    /** The signal's name in the text (SIGABRT), for the exception's type. */
    static String signal(String text) {
        for (String l : text.split("\n", -1)) {
            if (!l.startsWith("signal ")) continue;
            int open = l.indexOf('(');
            String after = open >= 0 ? l.substring(open + 1) : l;
            int close = after.indexOf(')');
            String name = close >= 0 ? after.substring(0, close) : after;
            return name.isEmpty() ? null : name;
        }
        return null;
    }

    /** The crashing thread's frames, top first, as {@code file (function)} without addresses or offsets: what stays
     *  the same from one build or run to the next. */
    static List<String> frames(String text) {
        List<String> out = new ArrayList<>();
        String[] lines = text.split("\n", -1);
        int i = 0;
        while (i < lines.length && !lines[i].equals("backtrace:")) i++;
        for (i++; i < lines.length && lines[i].startsWith("  #"); i++) {
            String line = lines[i];
            int pc = line.indexOf("  pc ");
            String rest = pc >= 0 ? line.substring(pc + 5) : line;
            int sp = rest.indexOf("  ");
            rest = sp >= 0 ? rest.substring(sp + 2) : rest;
            int paren = rest.indexOf(" (");
            String file = paren >= 0 ? rest.substring(0, paren) : rest;
            file = file.substring(file.lastIndexOf('/') + 1);
            String function = "";
            if (paren >= 0) {
                function = rest.substring(paren + 2);
                int plus = function.lastIndexOf('+');
                if (plus >= 0) function = function.substring(0, plus);
            }
            out.add(function.isEmpty() ? file : file + " (" + function + ")");
        }
        return out;
    }

    private static String read(byte[] bytes) {
        int[] pid = {0}, tid = {0};
        String[] abort = {""}, signal = {""}, fingerprint = {""};
        List<String> command = new ArrayList<>();
        Map<Integer, Thread> threads = new LinkedHashMap<>();
        List<Log> logs = new ArrayList<>();
        new Proto(bytes, 0, bytes.length).fields((n, f) -> {
            switch (n) {
                case 2: fingerprint[0] = f.string(); break;
                case 5: pid[0] = f.integer(); break;
                case 6: tid[0] = f.integer(); break;
                case 9: command.add(f.string()); break;
                case 10: signal[0] = signal(f.message()); break;
                case 14: abort[0] = f.string(); break;
                case 16: f.message().fields((k, e) -> { if (k == 2) { Thread t = thread(e.message()); threads.put(t.id, t); } }); break;
                case 18: f.message().fields((k, e) -> { if (k == 2) logs.add(log(e.message())); }); break;
                default: break;
            }
        });
        if (pid[0] == 0 && signal[0].isEmpty() && threads.isEmpty()) return null;
        Thread crashed = threads.get(tid[0]);
        StringBuilder b = new StringBuilder();
        if (!fingerprint[0].isEmpty()) b.append("Build fingerprint: '").append(fingerprint[0]).append("'\n");
        b.append("pid: ").append(pid[0]).append(", tid: ").append(tid[0]).append(", name: ").append(crashed != null ? crashed.name : "?")
                .append("  >>> ").append(String.join(" ", command)).append(" <<<\n");
        if (!signal[0].isEmpty()) b.append(signal[0]).append('\n');
        if (!abort[0].isEmpty()) b.append("Abort message: '").append(abort[0]).append("'\n");
        if (crashed != null) {
            b.append("\nbacktrace:\n");
            frames(b, crashed, 64);
        }
        // Warnings and errors only: the app's own lines that say what went wrong, not whatever else it logged.
        List<Log> worth = new ArrayList<>();
        for (Log l : logs) if (l.priority >= 5) worth.add(l);
        if (worth.size() > 50) worth = worth.subList(worth.size() - 50, worth.size());
        if (!worth.isEmpty()) {
            b.append("\n--- log (warnings and errors, last ").append(worth.size()).append(") ---\n");
            String p = "VDIWEF";
            for (Log l : worth) {
                char c = l.priority - 2 >= 0 && l.priority - 2 < p.length() ? p.charAt(l.priority - 2) : '?';
                b.append(l.time).append(' ').append(l.pid).append(' ').append(l.tid).append(' ').append(c).append(' ')
                        .append(l.tag).append(": ").append(l.message).append('\n');
            }
        }
        for (Thread t : threads.values()) {
            if (t.id == tid[0]) continue;
            b.append("\n\"").append(t.name).append("\" tid=").append(t.id).append('\n');
            frames(b, t, 8);
        }
        return b.toString();
    }

    private static void frames(StringBuilder b, Thread t, int most) {
        for (int i = 0; i < t.frames.size() && i < most; i++) {
            Frame f = t.frames.get(i);
            String pc = Long.toHexString(f.pc);
            b.append("  #").append(i < 10 ? "0" : "").append(i).append(" pc ");
            for (int k = pc.length(); k < 16; k++) b.append('0');
            b.append(pc).append("  ").append(f.file);
            if (!f.function.isEmpty()) b.append(" (").append(f.function).append('+').append(f.offset).append(')');
            b.append('\n');
        }
    }

    private static String signal(Proto m) {
        int[] number = {0}, code = {0};
        String[] name = {""}, codeName = {""};
        Long[] fault = {null};
        m.fields((n, f) -> {
            switch (n) {
                case 1: number[0] = f.integer(); break;
                case 2: name[0] = f.string(); break;
                case 3: code[0] = f.integer(); break;
                case 4: codeName[0] = f.string(); break;
                case 9: fault[0] = f.value; break;
                default: break;
            }
        });
        return "signal " + number[0] + " (" + name[0] + "), code " + code[0] + " (" + codeName[0] + ")"
                + (fault[0] != null ? ", fault addr 0x" + Long.toHexString(fault[0]) : "");
    }

    private static Thread thread(Proto m) {
        Thread t = new Thread();
        m.fields((n, f) -> {
            switch (n) {
                case 1: t.id = f.integer(); break;
                case 2: t.name = f.string(); break;
                case 4: t.frames.add(frame(f.message())); break;
                default: break;
            }
        });
        return t;
    }

    private static Frame frame(Proto m) {
        Frame fr = new Frame();
        m.fields((n, f) -> {
            switch (n) {
                case 1: fr.pc = f.value; break;
                case 4: fr.function = f.string(); break;
                case 5: fr.offset = f.value; break;
                case 6: fr.file = f.string(); break;
                default: break;
            }
        });
        return fr;
    }

    private static Log log(Proto m) {
        Log l = new Log();
        m.fields((n, f) -> {
            switch (n) {
                case 1: l.time = f.string(); break;
                case 2: l.pid = f.integer(); break;
                case 3: l.tid = f.integer(); break;
                case 4: l.priority = f.integer(); break;
                case 5: l.tag = f.string(); break;
                case 6: l.message = f.string(); break;
                default: break;
            }
        });
        return l;
    }

    /** The runs of printable text in what could not be read as a tombstone. */
    private static String strings(byte[] bytes) {
        StringBuilder out = new StringBuilder();
        int start = -1;
        for (int i = 0; i <= bytes.length; i++) {
            int b = i < bytes.length ? bytes[i] & 0xff : 0;
            boolean printable = b == 0x09 || (b >= 0x20 && b <= 0x7e) || b >= 0x80;
            if (printable && start < 0) start = i;
            if (!printable && start >= 0) {
                if (i - start >= 6) out.append(new String(bytes, start, i - start, StandardCharsets.UTF_8)).append('\n');
                start = -1;
                if (out.length() > Crashes.LOGS) break;
            }
        }
        return out.toString();
    }

    private interface Each {
        void field(int n, Proto.Field f);
    }

    /** One protobuf message: its fields in order, each a varint ({@code value}) or a length-delimited span. */
    private static final class Proto {
        final byte[] bytes;
        final int from, to;
        private int i;

        Proto(byte[] bytes, int from, int to) {
            this.bytes = bytes;
            this.from = from;
            this.to = to;
        }

        static final class Field {
            final byte[] bytes;
            final long value;
            final int start, end;

            Field(byte[] bytes, long value, int start, int end) {
                this.bytes = bytes;
                this.value = value;
                this.start = start;
                this.end = end;
            }

            int integer() { return (int) value; }

            String string() { return new String(bytes, start, end - start, StandardCharsets.UTF_8); }

            Proto message() { return new Proto(bytes, start, end); }
        }

        private long varint() {
            long v = 0;
            int shift = 0;
            while (true) {
                if (i >= to) throw new IllegalArgumentException("cut off");
                int b = bytes[i++] & 0xff;
                v |= (long) (b & 0x7f) << shift;
                if (b < 0x80) return v;
                shift += 7;
                if (shift >= 64) throw new IllegalArgumentException("varint");
            }
        }

        void fields(Each each) {
            i = from;
            while (i < to) {
                long tag = varint();
                int n = (int) (tag >>> 3);
                switch ((int) (tag & 7)) {
                    case 0: each.field(n, new Field(bytes, varint(), 0, 0)); break;
                    case 1: if (i + 8 > to) throw new IllegalArgumentException("cut off"); i += 8; break;
                    case 2: {
                        int len = (int) varint();
                        if (len < 0 || i + len > to) throw new IllegalArgumentException("cut off");
                        int s = i;
                        i += len;
                        each.field(n, new Field(bytes, 0, s, s + len));
                        break;
                    }
                    case 5: if (i + 4 > to) throw new IllegalArgumentException("cut off"); i += 4; break;
                    default: throw new IllegalArgumentException("wire type");
                }
            }
        }
    }
}
