// The station's local API for a module (docs/station-modules.md): HTTP/1.1 on a socket of its own
// (STILLFAIL_STATION_SOCKET, mode 600), each request with the module's token (`authorization: Bearer <token>`) and the
// member it acts for (`stillfail-viewer`, as the station told it: modules.ts viewerHeader). The drive is the station's,
// with its rules for that member (a viewer reaches the folders pinned in their workspace only, a member who may write
// any folder; the station's own data never; the folders macOS protects through still.fail Helper), answered by the
// drive's own routes (api/routes/drive.ts) as the admin API answers them:
//
//   GET /drive/list?root&path   /drive/stat?root&path   /drive/read?root&path&offset&length   /drive/watch?root&path&id
//   GET /thumb?root&path        an image's thumbnail (stillfail-thumbhash, -width, -height: the ThumbHash of what is sent)
//   GET /poster?root&path       a video's poster, a JPEG
//
// Reads only: what a module changes of the drive it changes as the member would, through the admin API.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { chmodSync, rmSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { type Answer, type Request, error, langOfCore, param, queryPairs } from "../api/request.ts";
import type { Route } from "../api/admin.ts";
import { driveOf, refused, routes as driveRoutes } from "../api/routes/drive.ts";
import type { Drive } from "../drive/drive.ts";
import type { ConfigFile } from "../ops/config.ts";
import { readOnly } from "../mesh/credential.ts";
import type { Codecs } from "../sessions/thumbs.ts";
import { log } from "../ops/log.ts";
import { VIEWER_HEADER, viewerOfHeader } from "./modules.ts";
import { posterOf, thumbOf } from "./media.ts";

export type LocalDeps = {
  drive: Drive;
  config: ConfigFile;
  /// <data>/thumbs: the drive's thumbnails and posters are kept under it (media.ts).
  thumbs: string;
  /// The module's token now (new each time it is started).
  token: () => string;
  /// The image codecs (the native addon's when not given).
  codecs?: Codecs | null;
};

/// The drive's reads a module makes, as the admin API has them.
const DRIVE_READS = ["/drive/list", "/drive/stat", "/drive/read", "/drive/watch"];

const authorized = (said: string | undefined, token: string) => {
  const want = Buffer.from(`Bearer ${token}`);
  const got = Buffer.from(said ?? "");
  return token !== "" && got.length === want.length && timingSafeEqual(got, want);
};

/// What answers a module's requests (its server listens on its socket: `listen`).
export function localApi(deps: LocalDeps): (req: IncomingMessage) => Promise<Answer> {
  const reads: Route[] = driveRoutes({ drive: deps.drive, config: deps.config }).filter((r) => r.method === "GET" && DRIVE_READS.some((p) => r.pattern.test(p)));
  const at = (r: Request) => ({ root: param(r, "root") ?? "", path: param(r, "path") ?? "", anywhere: !readOnly(r.viewer) });
  return async (req) => {
    if (!authorized(req.headers.authorization, deps.token())) return error(401, "not this module's token");
    const viewer = viewerOfHeader(typeof req.headers[VIEWER_HEADER] === "string" ? (req.headers[VIEWER_HEADER] as string) : undefined);
    if (viewer === null) return error(400, `${VIEWER_HEADER}: the member the module acts for, as it was told`);
    if (req.method !== "GET") return error(405, "the station's local API only reads");
    const url = new URL(req.url ?? "/", "http://station");
    const headers = Object.fromEntries(Object.entries(req.headers).flatMap(([k, v]): [string, string][] => (typeof v === "string" ? [[k, v]] : [])));
    const r: Request = { method: "GET", path: url.pathname, query: queryPairs(url.search.slice(1)), search: url.search, headers, body: Buffer.alloc(0), viewer, lang: langOfCore({ "stillfail-lang": "en", ...headers }) };
    try {
      if (r.path === "/thumb") {
        const shown = await thumbOf(driveOf(deps.drive, r), at(r), deps.thumbs, deps.codecs);
        if (shown === null) return error(404, "no thumbnail of that file");
        const hash: Record<string, string> = shown.hash === null ? {} : { "stillfail-thumbhash": shown.hash.hash, "stillfail-width": String(shown.hash.width), "stillfail-height": String(shown.hash.height) };
        return { status: 200, headers: { "content-type": shown.type, "cache-control": "no-store", ...hash }, body: shown.bytes };
      }
      if (r.path === "/poster") {
        const made = await posterOf(driveOf(deps.drive, r), at(r), deps.thumbs);
        if (made === null) return error(404, "no poster of that file");
        return { status: 200, headers: { "content-type": "image/jpeg", "cache-control": "no-store" }, body: await readFile(made) };
      }
    } catch (e) {
      return refused(e, r.lang);
    }
    for (const route of reads) {
      const found = route.pattern.exec(r.path);
      if (found) return route.handle(r, found.slice(1));
    }
    return error(404, `no route GET ${r.path}`);
  };
}

/// An answer onto the module's response: whole, or as it comes until either side ends.
async function send(res: ServerResponse, answer: Answer) {
  res.writeHead(answer.status, answer.headers);
  if (Buffer.isBuffer(answer.body)) {
    res.end(answer.body);
    return;
  }
  const chunks = answer.body[Symbol.asyncIterator]();
  const end = () => void chunks.return?.();
  res.once("close", end);
  try {
    for (let next = await chunks.next(); !next.done && !res.destroyed; next = await chunks.next()) {
      if (!res.write(next.value)) await new Promise<void>((r) => (res.once("drain", r), res.once("close", r)));
    }
    res.end();
  } finally {
    end();
  }
}

/// The local API listening at `socket` (any left there before removed), readable and writable by the station's user
/// only; closed (and the socket removed) by `close`.
export function listen(socket: string, answer: (req: IncomingMessage) => Promise<Answer>): Promise<Server> {
  rmSync(socket, { force: true });
  const server = createServer((req, res) => {
    // Its body (none is asked for) is not read.
    req.resume();
    answer(req)
      .then((a) => send(res, a))
      .catch((e) => {
        log.warn("modules", "a module's request to the station failed", { error: (e as Error).message });
        if (!res.headersSent) res.writeHead(500, { "content-type": "application/json" }).end(JSON.stringify({ error: (e as Error).message }));
        else res.destroy();
      });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socket, () => {
      server.off("error", reject);
      chmodSync(socket, 0o600);
      resolve(server);
    });
  });
}
