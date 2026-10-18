// What the media service's tests share: a zip writer (to make EPUBs), tiny image headers, a fake station local API
// serving files from memory, and the service started on sockets of its own with a client for it.
import { crc32, deflateRawSync } from "node:zlib";
import { createServer, request, type IncomingMessage } from "node:http";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, posix } from "node:path";
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

/// A station's local API over a unix socket, serving `files` (paths under the root `/books`) to the right token;
/// reads answer at most `part` bytes. `reads` counts the reads; `viewers` the viewer headers it was sent.
export async function fakeStation(dir: string, token: string, part = 4096) {
  const files = new Map<string, FakeFile>();
  const seen = { reads: 0, viewers: [] as string[] };
  const socket = join(dir, "st.sock");
  const reply = (res: import("node:http").ServerResponse, status: number, body: unknown) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  };
  const server = createServer((req: IncomingMessage, res) => {
    const url = new URL(req.url ?? "/", "http://station");
    if (req.headers.authorization !== `Bearer ${token}`) return reply(res, 401, { error: "bad token", code: "unauthorized" });
    seen.viewers.push(String(req.headers["stillfail-viewer"]));
    const root = url.searchParams.get("root");
    const path = posix.normalize(url.searchParams.get("path") ?? "").replace(/^\.$|^\/+|\/+$/g, "");
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
  return { socket, files, seen, close: () => new Promise<void>((done) => server.close(() => done())) };
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

/// The service started on a socket of its own, with a fake station; `stop` ends both.
export async function started(part = 4096) {
  const dir = mkdtempSync(join(tmpdir(), "media-"));
  const token = "secret-token";
  const station = await fakeStation(dir, token, part);
  const socket = join(dir, "m.sock");
  const service: Service = await startService({ dir: join(dir, "data"), socket, station: { socket: station.socket, token } });
  return {
    dir,
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
