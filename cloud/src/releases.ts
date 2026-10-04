// A file of the releases bucket, served at /releases/<file> (install.ts releaseType says which): whole, or the byte
// ranges asked for. The desktop app's updater (electron-updater) downloads an update differentially: it compares the
// blockmaps of the zip it has and the new one, and asks for what changed as up to a thousand ranges in a request,
// answered as multipart/byteranges. The bucket reads one range at a time, so ranges near each other are read as one.

/** The part of R2Bucket this needs. */
export interface ReleaseBucket {
  head(key: string): Promise<{ size: number; httpEtag: string } | null>;
  get(key: string, options?: { range?: { offset: number; length: number } }): Promise<{ body: ReadableStream<Uint8Array>; size: number; httpEtag: string } | null>;
}

/** A range asked for: the first byte and the one after the last. */
type Range = { start: number; end: number };

/** Reads that would be more than this many are made from ranges further apart, reading the bytes between. */
const MAX_READS = 40;

/** A file named by its version (a build's zip and its blockmap, an apk, a Node) never changes; the rest do (the feeds, the station's). */
const VERSIONED = /-[0-9.]+-arm64-mac\.zip(\.blockmap)?$|-[0-9]+\.apk$|^node\/node-v[0-9.]+-[a-z0-9-]+\.tar\.gz(\.sha256)?$/;

export async function serveRelease(request: Request, bucket: ReleaseBucket | undefined, file: string, type: string): Promise<Response> {
  const headers = {
    "content-type": type,
    "accept-ranges": "bytes",
    "cache-control": VERSIONED.test(file) ? "public, max-age=31536000, immutable" : "no-store",
  };
  const asked = request.headers.get("range");
  if (!asked) {
    const object = await bucket?.get(file);
    if (!object) return notFound();
    return new Response(object.body, { headers: { ...headers, etag: object.httpEtag, "content-length": String(object.size) } });
  }
  const head = await bucket?.head(file);
  if (!head) return notFound();
  const size = head.size;
  const ranges = parseRanges(asked, size);
  // Not a range this understands: the whole file, as for a request without one.
  if (ranges === null) return serveRelease(new Request(request.url), bucket, file, type);
  if (!ranges.length) return new Response(null, { status: 416, headers: { ...headers, "content-range": `bytes */${size}` } });
  const etag = { etag: head.httpEtag };
  if (ranges.length === 1) {
    const [{ start, end }] = ranges as [Range];
    const object = await bucket!.get(file, { range: { offset: start, length: end - start } });
    if (!object) return notFound();
    return new Response(object.body, { status: 206, headers: { ...headers, ...etag, "content-range": `bytes ${start}-${end - 1}/${size}`, "content-length": String(end - start) } });
  }
  const boundary = crypto.randomUUID().replaceAll("-", "");
  const encoder = new TextEncoder();
  // As electron-updater's DataSplitter reads it: the first boundary with no line before it, each part's bytes, then
  // the next boundary on a line of its own.
  const partHead = (range: Range, first: boolean) => encoder.encode(
    `${first ? "" : "\r\n"}--${boundary}\r\ncontent-type: ${type}\r\ncontent-range: bytes ${range.start}-${range.end - 1}/${size}\r\n\r\n`,
  );
  const tail = encoder.encode(`\r\n--${boundary}--\r\n`);
  const length = ranges.reduce((sum, range, i) => sum + partHead(range, i === 0).length + range.end - range.start, tail.length);
  const reads = groupReads(ranges);
  const { readable, writable } = new FixedLengthStream(length);
  const write = async () => {
    const out = writable.getWriter();
    try {
      let part = 0;
      for (const read of reads) {
        const object = await bucket!.get(file, { range: { offset: read.start, length: read.end - read.start } });
        if (!object) throw new Error(`${file} went away`);
        // The parts in this read (ascending, apart), cut out of its bytes as they come.
        let at = read.start;
        for await (const chunk of object.body as unknown as AsyncIterable<Uint8Array>) {
          let offset = 0;
          while (offset < chunk.length && part <= read.last) {
            const range = ranges[part]!;
            if (at < range.start) {
              const skip = Math.min(range.start - at, chunk.length - offset);
              offset += skip;
              at += skip;
              continue;
            }
            if (at === range.start) await out.write(partHead(range, part === 0));
            const take = Math.min(range.end - at, chunk.length - offset);
            await out.write(chunk.subarray(offset, offset + take));
            offset += take;
            at += take;
            if (at === range.end) part++;
          }
        }
        if (part !== read.last + 1) throw new Error(`${file} ended early`);
      }
      await out.write(tail);
      await out.close();
    } catch (error) {
      await out.abort(error);
    }
  };
  // The Worker is done with the request once the answer is written out; the writing goes on while it is read.
  void write();
  return new Response(readable, {
    status: 206,
    headers: { ...headers, ...etag, "content-type": `multipart/byteranges; boundary=${boundary}`, "content-length": String(length) },
  });
}

const notFound = () => Response.json({ error: "release_not_found" }, { status: 404, headers: { "cache-control": "no-store" } });

/**
 * The ranges of a Range header, in the order asked (RFC 9110 14.1.2: first-last, first-, -suffix), within a file of
 * `size` bytes: none if none of them is in it (416), null if the header is not one this reads (answered with the whole file).
 */
export function parseRanges(header: string, size: number): Range[] | null {
  const spec = /^\s*bytes\s*=\s*(.+)$/i.exec(header)?.[1];
  if (!spec) return null;
  const ranges: Range[] = [];
  for (const item of spec.split(",")) {
    const m = /^\s*(\d*)\s*-\s*(\d*)\s*$/.exec(item);
    if (!m || (m[1] === "" && m[2] === "")) return null;
    if (m[1] === "") {
      const suffix = Number(m[2]);
      if (suffix > 0 && size > 0) ranges.push({ start: Math.max(0, size - suffix), end: size });
      continue;
    }
    const start = Number(m[1]);
    if (m[2] !== "" && Number(m[2]) < start) return null;
    if (start < size) ranges.push({ start, end: m[2] === "" ? size : Math.min(Number(m[2]) + 1, size) });
  }
  return ranges;
}

/**
 * The reads of the bucket that give the ranges, in order: runs of ranges read as one, each ending at range `last`,
 * so there are at most MAX_READS of them (reading the bytes between, which stay in Cloudflare) — fewer where ranges
 * are asked out of order.
 */
export function groupReads(ranges: Range[]): { start: number; end: number; last: number }[] {
  for (let gap = 64 * 1024; ; gap *= 2) {
    const reads: { start: number; end: number; last: number }[] = [];
    ranges.forEach((range, i) => {
      const read = reads.at(-1);
      if (read && range.start >= read.end && range.start - read.end <= gap) {
        read.end = range.end;
        read.last = i;
      } else {
        reads.push({ start: range.start, end: range.end, last: i });
      }
    });
    if (reads.length <= MAX_READS || gap > 2 ** 40) return reads;
  }
}

/** Each app's feed: the released builds', and the beta apps' (fail.still.*.beta, for testers: /releases/latest/<app>-beta). */
const FEEDS: Record<string, string> = {
  mac: "desktop/stillfail-mac.yml",
  android: "android/latest.json",
  "mac-beta": "desktop/stillfail-beta-mac.yml",
  "android-beta": "android/beta/latest.json",
};

/**
 * The latest build of an app, for a link that does not change (the site's downloads, /releases/latest/<app>): where its
 * updater's feed says it is, as a path under /releases/; null while there is none.
 */
export async function latestDownload(bucket: ReleaseBucket | undefined, app: string): Promise<string | null> {
  const feed = FEEDS[app];
  const object = feed ? await bucket?.get(feed) : null;
  if (!object) return null;
  const text = await new Response(object.body).text();
  if (app.startsWith("mac")) {
    const file = /^path:\s*(\S+)\s*$/m.exec(text)?.[1];
    return file ? `desktop/${file}` : null;
  }
  try {
    const file = (JSON.parse(text) as { file?: unknown }).file;
    return typeof file === "string" ? file : null;
  } catch {
    return null;
  }
}
