// What the media service's tests share: a zip writer (to make EPUBs), tiny image headers, a fake station local API
// serving files from memory, and the service started on sockets of its own with a client for it.
import { crc32, deflateRawSync } from "node:zlib";
import { createServer, request, type IncomingMessage } from "node:http";
import { mkdtempSync, realpathSync } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, posix } from "node:path";
import { sniff } from "../src/images.ts";
import type { Tools } from "../src/ffmpeg.ts";
import { startService, type Service } from "../src/server.ts";

/// A zip of `files` (deflated unless `stored`), as an EPUB wants it when `mimetype` comes first and stored.
export function zip(files: { name: string; data: string | Buffer; stored?: boolean }[]): Buffer {
  const parts: Buffer[] = [];
  const central: Buffer[] = [];
  let at = 0;
  for (const f of files) {
    const body = typeof f.data === "string" ? Buffer.from(f.data, "utf8") : f.data;
    const packed = f.stored ? body : deflateRawSync(body);
    const method = f.stored ? 0 : 8;
    const name = Buffer.from(f.name, "utf8");
    const crc = crc32(body) >>> 0;
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0);
    h.writeUInt16LE(20, 4);
    h.writeUInt16LE(0x0800, 6);
    h.writeUInt16LE(method, 8);
    h.writeUInt32LE(crc, 14);
    h.writeUInt32LE(packed.length, 18);
    h.writeUInt32LE(body.length, 22);
    h.writeUInt16LE(name.length, 26);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(20, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt16LE(0x0800, 8);
    c.writeUInt16LE(method, 10);
    c.writeUInt32LE(crc, 16);
    c.writeUInt32LE(packed.length, 20);
    c.writeUInt32LE(body.length, 24);
    c.writeUInt16LE(name.length, 28);
    c.writeUInt32LE(at, 42);
    central.push(c, name);
    parts.push(h, name, packed);
    at += h.length + name.length + packed.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(at, 16);
  return Buffer.concat([...parts, cd, end]);
}

/// The start of a PNG of `w`×`h` (enough for its size to be read).
export function png(w: number, h: number): Buffer {
  const b = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b, 0);
  b.writeUInt32BE(13, 8);
  b.write("IHDR", 12, "latin1");
  b.writeUInt32BE(w, 16);
  b.writeUInt32BE(h, 20);
  b[24] = 8;
  b[25] = 6;
  return b;
}

/// The start of a baseline JPEG of `w`×`h`: SOI, an APP0, SOF0.
export function jpeg(w: number, h: number): Buffer {
  const app0 = Buffer.from([0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  const sof = Buffer.alloc(19);
  sof.writeUInt16BE(0xffc0, 0);
  sof.writeUInt16BE(17, 2);
  sof[4] = 8;
  sof.writeUInt16BE(h, 5);
  sof.writeUInt16BE(w, 7);
  sof[9] = 3;
  return Buffer.concat([Buffer.from([0xff, 0xd8]), app0, sof, Buffer.from([0xff, 0xd9])]);
}

const XHTML = (body: string, title = "") =>
  `<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>${title}</title><style>p { text-indent: 2em }</style></head>\n<body>${body}</body></html>`;

/// An EPUB 3 with a nav: a cover, two chapters (styles, ruby, an image, a rule), the second with a section under it.
export function epub3(): Buffer {
  const opf = `<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:test:1</dc:identifier>
    <dc:title>测试之书</dc:title>
    <dc:creator>张三</dc:creator>
    <dc:creator>李四</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="pic" href="images/pic%201.png" media-type="image/png"/>
    <item id="c0" href="text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="empty" href="text/empty.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c0"/>
    <itemref idref="c1"/>
    <itemref idref="empty"/>
    <itemref idref="c2"/>
  </spine>
</package>`;
  const nav = XHTML(`<nav epub:type="landmarks"><ol><li><a href="text/cover.xhtml">封面地标</a></li></ol></nav>
<nav epub:type="toc"><h1>目录</h1><ol>
  <li><a href="text/ch1.xhtml">第一章 开始</a></li>
  <li><a href="text/ch2.xhtml#top">第二部</a><ol><li><a href="text/ch2.xhtml#s1">小节</a></li></ol></li>
</ol></nav>`);
  const cover = XHTML(`<div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 600 800"><image width="600" height="800" xlink:href="../images/cover.jpg"/></svg></div>`);
  const ch1 = XHTML(`
    <h1 class="title">第一章&#x3000;开始</h1>
    <p>　　他说：&ldquo;你好，
       世界。&rdquo;</p>
    <p>这是<b>粗体</b>和<em>斜体</em>，还有<a href="https://example.com/x">链接</a>。</p>
    <p><ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp>字<rt>じ</rt></ruby>を読む</p>
    <p>第一行<br/>第二行</p>
    <hr/>
    <p><img src="../images/pic%201.png" alt="图"/></p>
    <script>document.write("不该出现")</script>
    <p>   </p>
    <p>A &amp; B &lt; C &#169;</p>`);
  const ch2 = XHTML(`<h2 id="top">第二部</h2><p id="s1">最后一段。</p>`);
  const empty = XHTML(`<div>  </div>`);
  return zip([
    { name: "mimetype", data: "application/epub+zip", stored: true },
    { name: "META-INF/container.xml", data: `<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>` },
    { name: "OEBPS/content.opf", data: opf },
    { name: "OEBPS/nav.xhtml", data: nav },
    { name: "OEBPS/text/cover.xhtml", data: cover },
    { name: "OEBPS/text/ch1.xhtml", data: ch1 },
    { name: "OEBPS/text/ch2.xhtml", data: ch2 },
    { name: "OEBPS/text/empty.xhtml", data: empty },
    { name: "OEBPS/images/cover.jpg", data: jpeg(600, 800) },
    { name: "OEBPS/images/pic 1.png", data: png(320, 240), stored: true },
  ]);
}

/// An EPUB 2 with only a toc.ncx (nested), one chapter it does not name, and <meta name="cover">.
export function epub2(): Buffer {
  const opf = `<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Old Book</dc:title><dc:creator opf:role="aut">Ann Author</dc:creator>
    <meta name="cover" content="cov"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cov" href="cover.png" media-type="image/png"/>
    <item id="a" href="a.html" media-type="application/xhtml+xml"/>
    <item id="b" href="b.html" media-type="application/xhtml+xml"/>
    <item id="c" href="c.html" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/><itemref idref="c"/></spine>
</package>`;
  const ncx = `<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
  <navPoint id="p1"><navLabel><text>Part One</text></navLabel><content src="a.html"/>
    <navPoint id="p2"><navLabel><text>Chapter 1</text></navLabel><content src="b.html#x"/></navPoint>
  </navPoint>
</navMap></ncx>`;
  return zip([
    { name: "mimetype", data: "application/epub+zip", stored: true },
    { name: "META-INF/container.xml", data: `<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>` },
    { name: "content.opf", data: opf },
    { name: "toc.ncx", data: ncx },
    { name: "cover.png", data: png(10, 20) },
    { name: "a.html", data: `<html><body><p>Part one starts.</p></body></html>` },
    { name: "b.html", data: `<html><body><h3>B heading</h3><p>Some <strong>bold <i>both</i></strong> text.</p></body></html>` },
    { name: "c.html", data: `<html><body><h2>Unnamed &amp; found</h2><p>End.</p></body></html>` },
  ]);
}

/// The GB18030 bytes of `text` (by a table of the characters used: Node encodes only UTF-8).
export function gb18030(text: string): Buffer {
  const decoder = new TextDecoder("gb18030");
  const table = new Map<string, Buffer>();
  for (let hi = 0x81; hi <= 0xfe; hi++) {
    for (let lo = 0x40; lo <= 0xfe; lo++) {
      if (lo === 0x7f) continue;
      const b = Buffer.from([hi, lo]);
      const ch = decoder.decode(b);
      if (ch.length === 1 && ch !== "�" && !table.has(ch)) table.set(ch, b);
    }
  }
  const out: Buffer[] = [];
  for (const ch of text) {
    if (ch.charCodeAt(0) < 0x80) out.push(Buffer.from(ch, "latin1"));
    else {
      const b = table.get(ch);
      if (!b) throw new Error(`no GB18030 two-byte code for ${ch}`);
      out.push(b);
    }
  }
  return Buffer.concat(out);
}

export type FakeFile = { bytes: Buffer; mtime: number };

/// The poster the fake station makes of every video.
export const POSTER = () => jpeg(640, 360);

/// A station's local API over a unix socket, serving `files` (paths under the root `/books`) to the right token, and
/// the disk under `dir` (any root there: the photo library's folders); reads answer at most `part` bytes. `reads`
/// counts the reads; `viewers` the viewer headers it was sent, `asked` with what for; `thumbs` and `posters` the
/// pictures it made. A disk folder's watch (as the station's: each asker's kept between its askings) answers true once
/// the test says the folder changed (`changed`: no watch of the disk's own, whose events came late or not at all,
/// 39476782243), false after `held` ms. `/thumb` answers a png/jpg/jpeg/webp itself with a made-up ThumbHash; `/poster` POSTER.
export async function fakeStation(dir: string, token: string, part = 4096, held = 2000) {
  const files = new Map<string, FakeFile>();
  const seen = { reads: 0, viewers: [] as string[], asked: [] as { route: string; root: string; path: string; viewer: string }[], thumbs: 0, posters: 0 };
  const socket = join(dir, "st.sock");
  const watches = new Map<string, { dir: string; changed: boolean; waiting: Set<() => void> }>();
  const reply = (res: import("node:http").ServerResponse, status: number, body: unknown) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  };
  const onDisk = async (res: import("node:http").ServerResponse, route: string, root: string, path: string, url: URL) => {
    const full = join(root, path);
    const st = await stat(full).catch(() => null);
    const missing = () => reply(res, 404, { error: "not found", code: "not_found" });
    const entry = (name: string, s: import("node:fs").Stats) => ({ name, dir: s.isDirectory(), size: s.isDirectory() ? 0 : s.size, mtime: Math.round(s.mtimeMs), type: "" });
    if (route === "/drive/stat") return st ? reply(res, 200, entry(posix.basename(path), st)) : missing();
    if (route === "/drive/list") {
      if (!st?.isDirectory()) return missing();
      const entries = [];
      for (const name of await readdir(full)) {
        const s = await stat(join(full, name)).catch(() => null);
        if (s) entries.push(entry(name, s));
      }
      return reply(res, 200, { path, entries, truncated: false });
    }
    if (route === "/drive/read") {
      if (!st?.isFile()) return missing();
      seen.reads++;
      const offset = Number(url.searchParams.get("offset") ?? 0);
      const length = Math.min(Number(url.searchParams.get("length") ?? part), part, 8 * 1024 * 1024);
      const all = await readFile(full);
      res.writeHead(200, { "content-type": "application/octet-stream", "stillfail-total": String(st.size), "stillfail-mtime": String(Math.round(st.mtimeMs)) });
      return res.end(all.subarray(offset, offset + length));
    }
    if (route === "/drive/watch") {
      if (!st?.isDirectory()) return missing();
      const key = `${url.searchParams.get("id")}\0${full}`;
      let w = watches.get(key);
      if (!w) {
        const made = { dir: full, changed: false, waiting: new Set<() => void>() };
        watches.set(key, made);
        w = made;
      }
      const watched = w;
      if (watched.changed) {
        watched.changed = false;
        return reply(res, 200, { changed: true });
      }
      const wake = () => {
        clearTimeout(timer);
        watched.waiting.delete(wake);
        watched.changed = false;
        reply(res, 200, { changed: true });
      };
      const timer = setTimeout(() => {
        watched.waiting.delete(wake);
        reply(res, 200, { changed: false });
      }, held);
      watched.waiting.add(wake);
      res.on("close", () => {
        clearTimeout(timer);
        watched.waiting.delete(wake);
      });
      return;
    }
    if (route === "/thumb") {
      if (!st?.isFile()) return missing();
      if (!/\.(png|jpe?g|webp)$/i.test(path)) return reply(res, 404, { error: "no thumbnail of that file" });
      seen.thumbs++;
      const bytes = await readFile(full);
      const s = sniff(bytes, "image/jpeg");
      res.writeHead(200, { "content-type": s.type, "stillfail-thumbhash": Buffer.from(`th:${posix.basename(path)}`).toString("base64"), "stillfail-width": String(s.w ?? 1), "stillfail-height": String(s.h ?? 1) });
      return res.end(bytes);
    }
    if (route === "/poster") {
      if (!st?.isFile()) return missing();
      if (!/\.(mp4|mov|m4v)$/i.test(path)) return reply(res, 404, { error: "no poster of that file" });
      seen.posters++;
      res.writeHead(200, { "content-type": "image/jpeg" });
      return res.end(POSTER());
    }
    reply(res, 404, { error: "no route", code: "not_found" });
  };
  const server = createServer((req: IncomingMessage, res) => {
    const url = new URL(req.url ?? "/", "http://station");
    if (req.headers.authorization !== `Bearer ${token}`) return reply(res, 401, { error: "bad token", code: "unauthorized" });
    seen.viewers.push(String(req.headers["stillfail-viewer"]));
    const root = url.searchParams.get("root");
    const path = posix.normalize(url.searchParams.get("path") ?? "").replace(/^\.$|^\/+|\/+$/g, "");
    seen.asked.push({ route: url.pathname, root: root ?? "", path, viewer: String(req.headers["stillfail-viewer"]) });
    if (root && (root === dir || root.startsWith(`${dir}/`)) && !path.split("/").includes("..")) {
      onDisk(res, url.pathname, root, path, url).catch((e) => reply(res, 500, { error: String(e) }));
      return;
    }
    if (root !== "/books") return reply(res, 404, { error: "not a root", code: "not_a_root" });
    const file = files.get(path);
    const isDir = path === "" || [...files.keys()].some((k) => k.startsWith(`${path}/`));
    const name = posix.basename(path);
    if (url.pathname === "/drive/stat") {
      if (file) return reply(res, 200, { name, dir: false, size: file.bytes.length, mtime: file.mtime, type: "application/octet-stream" });
      if (isDir) return reply(res, 200, { name, dir: true, size: 0, mtime: 1, type: "" });
      return reply(res, 404, { error: "not found", code: "not_found" });
    }
    if (url.pathname === "/drive/list") {
      if (!isDir) return reply(res, 404, { error: "not found", code: "not_found" });
      const entries = new Map<string, unknown>();
      for (const [k, f] of files) {
        const rest = path ? (k.startsWith(`${path}/`) ? k.slice(path.length + 1) : null) : k;
        if (rest === null) continue;
        const first = rest.split("/")[0]!;
        entries.set(first, rest.includes("/") ? { name: first, dir: true, size: 0, mtime: 1, type: "" } : { name: first, dir: false, size: f.bytes.length, mtime: f.mtime, type: "" });
      }
      return reply(res, 200, { path, entries: [...entries.values()], truncated: false });
    }
    if (url.pathname === "/drive/read") {
      if (!file) return reply(res, 404, { error: "not found", code: "not_found" });
      seen.reads++;
      const offset = Number(url.searchParams.get("offset") ?? 0);
      const length = Math.min(Number(url.searchParams.get("length") ?? part), part, 8 * 1024 * 1024);
      const bytes = file.bytes.subarray(offset, offset + length);
      res.writeHead(200, { "content-type": "application/octet-stream", "stillfail-total": String(file.bytes.length), "stillfail-mtime": String(file.mtime) });
      return res.end(bytes);
    }
    reply(res, 404, { error: "no route", code: "not_found" });
  });
  await new Promise<void>((done) => server.listen(socket, done));
  return {
    socket,
    files,
    seen,
    /// What the disk's watch would say of folder `dir` (a full path) after the test changed it: its watches woken.
    changed(dir: string) {
      for (const w of watches.values()) {
        if (w.dir !== dir) continue;
        w.changed = true;
        for (const wake of [...w.waiting]) wake();
      }
    },
    close: () =>
      new Promise<void>((done) => {
        server.close(() => done());
        server.closeAllConnections();
      }),
  };
}

export type Who = { sub: string; role: string; workspace: string; name?: string };

/// JSON as the station puts it in a header: every character from U+007F on escaped, so all ASCII.
export const ascii = (v: unknown) => JSON.stringify(v).replace(/[\u007f-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);

/// The header the station sends for `w`.
export const header = (w: Who) => ascii({ sub: w.sub, email: `${w.sub}@example.com`, name: w.name ?? "读者", role: w.role, workspace: w.workspace, home: true });

export type Answer = { status: number; headers: IncomingMessage["headers"]; bytes: Buffer; json: any };

/// A request to the service on `socket` as `who`.
export function call(socket: string, method: string, path: string, who: Who | null, body?: unknown): Promise<Answer> {
  return new Promise((done, fail) => {
    const headers: Record<string, string> = {};
    if (who) headers["stillfail-viewer"] = header(who);
    if (body !== undefined) headers["content-type"] = "application/json";
    const req = request({ socketPath: socket, method, path, headers }, (res) => {
      const parts: Buffer[] = [];
      res.on("data", (b: Buffer) => parts.push(b));
      res.on("end", () => {
        const bytes = Buffer.concat(parts);
        let json: any = null;
        if (String(res.headers["content-type"]).startsWith("application/json")) json = JSON.parse(bytes.toString("utf8"));
        done({ status: res.statusCode ?? 0, headers: res.headers, bytes, json });
      });
    });
    req.on("error", fail);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

/// A request with a body of bytes as it is.
export function callBytes(socket: string, method: string, path: string, who: Who | null, body: Buffer): Promise<Answer> {
  return new Promise((done, fail) => {
    const headers: Record<string, string> = { "content-type": "application/octet-stream", "content-length": String(body.length) };
    if (who) headers["stillfail-viewer"] = header(who);
    const req = request({ socketPath: socket, method, path, headers }, (res) => {
      const parts: Buffer[] = [];
      res.on("data", (b: Buffer) => parts.push(b));
      res.on("end", () => {
        const bytes = Buffer.concat(parts);
        done({ status: res.statusCode ?? 0, headers: res.headers, bytes, json: String(res.headers["content-type"]).startsWith("application/json") ? JSON.parse(bytes.toString("utf8")) : null });
      });
    });
    // The service may answer (refuse) before it took the whole body.
    req.on("error", (e) => ((e as NodeJS.ErrnoException).code === "EPIPE" || (e as NodeJS.ErrnoException).code === "ECONNRESET" ? undefined : fail(e)));
    req.end(body);
  });
}

// Photos and videos, as small as their headers.

/// A TIFF tag: its number, its type (2 ASCII, 3 SHORT, 4 LONG, 5 RATIONAL as [num, den, …]) and value.
export type Tag = [tag: number, type: number, value: string | number[]];

/// A TIFF (EXIF's): IFD0, with the Exif and GPS IFDs pointed to from it when given.
export function tiff(ifd0: Tag[], exif: Tag[] = [], gps: Tag[] = [], le = false): Buffer {
  const first: Tag[] = [...ifd0];
  if (exif.length) first.push([0x8769, 4, [0]]);
  if (gps.length) first.push([0x8825, 4, [0]]);
  const ifds = [first, exif, gps];
  const offsets: number[] = [];
  let at = 8;
  for (const t of ifds) {
    offsets.push(t.length ? at : 0);
    if (t.length) at += 2 + t.length * 12 + 4;
  }
  for (const t of first) {
    if (t[0] === 0x8769) t[2] = [offsets[1]!];
    if (t[0] === 0x8825) t[2] = [offsets[2]!];
  }
  const b = Buffer.alloc(at + 4096);
  const w16 = (v: number, o: number) => (le ? b.writeUInt16LE(v, o) : b.writeUInt16BE(v, o));
  const w32 = (v: number, o: number) => (le ? b.writeUInt32LE(v, o) : b.writeUInt32BE(v, o));
  b.write(le ? "II" : "MM", 0, "latin1");
  w16(42, 2);
  w32(8, 4);
  let data = at;
  ifds.forEach((tags, k) => {
    if (!tags.length) return;
    let p = offsets[k]!;
    w16(tags.length, p);
    p += 2;
    for (const [tag, type, value] of [...tags].sort((x, y) => x[0] - y[0])) {
      let bytes: Buffer;
      let count: number;
      if (type === 2) {
        bytes = Buffer.from(`${value as string}\0`, "latin1");
        count = bytes.length;
      } else {
        const nums = value as number[];
        const size = type === 3 ? 2 : 4;
        bytes = Buffer.alloc(nums.length * size);
        nums.forEach((n, i) => (size === 2 ? (le ? bytes.writeUInt16LE(n, i * 2) : bytes.writeUInt16BE(n, i * 2)) : le ? bytes.writeUInt32LE(n, i * 4) : bytes.writeUInt32BE(n, i * 4)));
        count = type === 5 ? nums.length / 2 : nums.length;
      }
      w16(tag, p);
      w16(type, p + 2);
      w32(count, p + 4);
      if (bytes.length <= 4) bytes.copy(b, p + 8);
      else {
        w32(data, p + 8);
        bytes.copy(b, data);
        data += bytes.length + (bytes.length & 1);
      }
      p += 12;
    }
    w32(0, p);
  });
  return b.subarray(0, data);
}

/// The EXIF of a phone's photo: taken 2024-05-01 10:20:30 +09:00, turned (6), an iPhone's camera and lens, in Tokyo.
export const PHONE_EXIF = (le = false) =>
  tiff(
    [[0x010f, 2, "Apple"], [0x0110, 2, "iPhone 15 Pro"], [0x0112, 3, [6]]],
    [[0x9003, 2, "2024:05:01 10:20:30"], [0x9011, 2, "+09:00"], [0xa434, 2, "iPhone 15 Pro back camera 6.86mm f/1.78"]],
    [[1, 2, "N"], [2, 5, [35, 1, 39, 1, 2952, 100]], [3, 2, "E"], [4, 5, [139, 1, 44, 1, 3024, 100]]],
    le,
  );

/// A JPEG of `w`×`h` (as stored) with `exif` in an APP1, then whatever `tail` is.
export function exifJpeg(w: number, h: number, exif: Buffer, tail = Buffer.alloc(0)): Buffer {
  const app1 = Buffer.alloc(4 + 6);
  app1.writeUInt16BE(0xffe1, 0);
  app1.writeUInt16BE(2 + 6 + exif.length, 2);
  app1.write("Exif\0\0", 4, "latin1");
  const plain = jpeg(w, h);
  return Buffer.concat([plain.subarray(0, 2), app1, exif, plain.subarray(2, plain.length - 2), tail, plain.subarray(plain.length - 2)]);
}

/// An ISO BMFF box (`full`: with version and flags).
export function box(type: string, body: Buffer | Buffer[], full?: { version: number; flags?: number }): Buffer {
  const inner = Buffer.concat([...(full ? [Buffer.from([full.version, ((full.flags ?? 0) >> 16) & 255, ((full.flags ?? 0) >> 8) & 255, (full.flags ?? 0) & 255])] : []), ...(Array.isArray(body) ? body : [body])]);
  const h = Buffer.alloc(8);
  h.writeUInt32BE(8 + inner.length, 0);
  h.write(type, 4, "latin1");
  return Buffer.concat([h, inner]);
}

const u16 = (v: number) => {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(v);
  return b;
};
const u32 = (v: number) => {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(v);
  return b;
};

/// A HEIC: its primary item (1) of `w`×`h` coded, turned a quarter (irot 1, or `rot`), its Exif item (2) in the mdat
/// after `pad` bytes of the image's own.
export function heic(w: number, h: number, exif: Buffer, pad = 0, rot = 1): Buffer {
  const ftyp = box("ftyp", [Buffer.from("heic", "latin1"), u32(0), Buffer.from("mif1heic", "latin1")]);
  const exifItem = Buffer.concat([u32(6), Buffer.from("Exif\0\0", "latin1"), exif]);
  const meta = (imageAt: number, exifAt: number) =>
    box(
      "meta",
      [
        box("hdlr", [u32(0), Buffer.from("pict", "latin1"), Buffer.alloc(12), Buffer.from("\0")], { version: 0 }),
        box("pitm", u16(1), { version: 0 }),
        box("iinf", [u16(2), box("infe", [u16(1), u16(0), Buffer.from("hvc1", "latin1"), Buffer.from("\0")], { version: 2 }), box("infe", [u16(2), u16(0), Buffer.from("Exif", "latin1"), Buffer.from("\0")], { version: 2 })], { version: 0 }),
        // offset_size 4, length_size 4, base_offset_size 0; two items of one extent each.
        box("iloc", [Buffer.from([0x44, 0x00]), u16(2), u16(1), u16(0), u16(1), u32(imageAt), u32(pad), u16(2), u16(0), u16(1), u32(exifAt), u32(exifItem.length)], { version: 0 }),
        box("iprp", [
          box("ipco", [box("ispe", [u32(w), u32(h)], { version: 0 }), box("irot", Buffer.from([rot]))]),
          box("ipma", [u32(1), u16(1), Buffer.from([2, 0x81, 0x02])], { version: 0 }),
        ]),
      ],
      { version: 0 },
    );
  const metaSize = meta(0, 0).length;
  const mdatAt = ftyp.length + metaSize;
  const imageAt = mdatAt + 8;
  const exifAt = imageAt + pad;
  return Buffer.concat([ftyp, meta(imageAt, exifAt), box("mdat", [Buffer.alloc(pad), exifItem])]);
}

/// An MP4 made at `created` (ms), `seconds` long, its video track `w`×`h` turned a quarter; the moov after `pad` bytes of
/// media data when `pad` is given.
export function mp4(created: number, seconds: number, w: number, h: number, pad = 0): Buffer {
  const ftyp = box("ftyp", [Buffer.from("isom", "latin1"), u32(512), Buffer.from("isomiso2mp41", "latin1")]);
  const when = Math.round(created / 1000) + 2_082_844_800;
  const mvhd = box("mvhd", [u32(when), u32(when), u32(1000), u32(Math.round(seconds * 1000)), u32(0x10000), u16(0x100), Buffer.alloc(10), Buffer.alloc(36), Buffer.alloc(24), u32(2)], { version: 0 });
  // A quarter turn: a = 0, b = 1, c = -1, d = 0.
  const matrix = Buffer.concat([u32(0), u32(0x10000), u32(0), u32(0xffff0000), u32(0), u32(0), u32(0), u32(0), u32(0x40000000)]);
  const tkhd = box("tkhd", [u32(when), u32(when), u32(1), u32(0), u32(Math.round(seconds * 1000)), Buffer.alloc(8), u16(0), u16(0), u16(0), u16(0), matrix, u32(w * 65536), u32(h * 65536)], { version: 0, flags: 3 });
  const audio = box("trak", box("tkhd", [u32(when), u32(when), u32(2), u32(0), u32(0), Buffer.alloc(8), u16(0), u16(1), u16(0x100), u16(0), Buffer.alloc(36), u32(0), u32(0)], { version: 0, flags: 3 }));
  const moov = box("moov", [mvhd, audio, box("trak", tkhd)]);
  const mdat = box("mdat", Buffer.alloc(pad));
  return pad ? Buffer.concat([ftyp, mdat, moov]) : Buffer.concat([ftyp, moov, mdat]);
}

/// A GIF's header of `w`×`h`.
export function gif(w: number, h: number): Buffer {
  const b = Buffer.alloc(13);
  b.write("GIF89a", 0, "latin1");
  b.writeUInt16LE(w, 6);
  b.writeUInt16LE(h, 8);
  return Buffer.concat([b, Buffer.from([0x3b])]);
}

/// A 24-bit BMP of `w`×`h` of one colour, bottom-up (as sips writes them, but for the row order).
export function bmp(w: number, h: number, rgb: [number, number, number]): Buffer {
  const stride = Math.ceil((w * 3) / 4) * 4;
  const b = Buffer.alloc(54 + stride * h);
  b.write("BM", 0, "latin1");
  b.writeUInt32LE(b.length, 2);
  b.writeUInt32LE(54, 10);
  b.writeUInt32LE(40, 14);
  b.writeInt32LE(w, 18);
  b.writeInt32LE(h, 22);
  b.writeUInt16LE(1, 26);
  b.writeUInt16LE(24, 28);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) b.set([rgb[2], rgb[1], rgb[0]], 54 + y * stride + x * 3);
  return b;
}

/// The events `/events` sends `who`, as they come; `close` ends the stream, `ended` is when it ended (either side).
export function listen(socket: string, who: Who) {
  const events: { event: string; data: any }[] = [];
  let buffer = "";
  let res: IncomingMessage | null = null;
  let ended!: () => void;
  const gone = new Promise<void>((done) => (ended = done));
  const ready = new Promise<void>((done, fail) => {
    const req = request({ socketPath: socket, method: "GET", path: "/events", headers: { "stillfail-viewer": header(who) } }, (r) => {
      res = r;
      r.on("close", ended);
      r.setEncoding("utf8");
      r.on("data", (chunk: string) => {
        buffer += chunk;
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const frame = buffer.slice(0, end);
          buffer = buffer.slice(end + 2);
          const event = /^event: (.*)$/m.exec(frame)?.[1];
          const data = /^data: (.*)$/m.exec(frame)?.[1];
          if (event) events.push({ event, data: data ? JSON.parse(data) : null });
          else if (frame.startsWith(": ok")) done();
        }
      });
    });
    req.on("error", fail);
    req.end();
  });
  return { events, ready, ended: gone, close: () => res?.destroy() };
}

export const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// The service started on a socket of its own, with a fake station; `stop` ends both. The photo library's backup
/// folder is `<dir>/backup`; `sips` none unless given; ffmpeg and ffprobe none unless given (`tools`), the HLS cache's
/// cap as `hlsCap` says.
export async function started(part = 4096, sips: string | null = null, tools: Tools = { ffmpeg: null, ffprobe: null }, hlsCap?: number) {
  // Short and real: a unix socket's path is at most 104 bytes on macOS, and the station is asked by real paths.
  const dir = realpathSync(mkdtempSync(join(process.platform === "darwin" ? "/tmp" : tmpdir(), "media-")));
  const token = "secret-token";
  const station = await fakeStation(dir, token, part);
  const socket = join(dir, "m.sock");
  const backup = join(dir, "backup");
  const service: Service = await startService({ dir: join(dir, "data"), socket, station: { socket: station.socket, token }, backup, sips, tools, ...(hlsCap ? { hlsCap } : {}) });
  return {
    dir,
    backup,
    station,
    socket,
    service,
    call: (method: string, path: string, who: Who | null, body?: unknown) => call(socket, method, path, who, body),
    stop: async () => {
      await service.close();
      await station.close();
    },
  };
}

export const OWNER: Who = { sub: "u-owner", role: "owner", workspace: "w1", name: "主人" };
export const MEMBER: Who = { sub: "u-member", role: "member", workspace: "w1" };
export const VIEWER: Who = { sub: "u-viewer", role: "viewer", workspace: "w1", name: "只读的人" };
export const OTHER: Who = { sub: "u-other", role: "owner", workspace: "w2" };
