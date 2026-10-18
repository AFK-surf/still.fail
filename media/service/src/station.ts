// The station's local API for modules (its socket, STILLFAIL_STATION_SOCKET): the drive's stat, list and parts of
// files, asked for the member the service acts for, so the station's rules (pinned folders for viewers, folders macOS
// protects, its own data) apply here as they do to the member's own client. The service never reads a drive path itself.
import { request } from "node:http";
import { MediaError } from "./errors.ts";

export type StationLink = { socket: string; token: string };

/// A drive entry as the station's drive gives it.
export type DriveEntry = { name: string; dir: boolean; size: number; mtime: number; type: string };

/// The most the station answers in one read.
export const PART = 8 * 1024 * 1024;

type Answer = { status: number; headers: Record<string, string | string[] | undefined>; body: Buffer };

function get(link: StationLink, viewer: string, path: string, query: Record<string, string | number>, signal?: AbortSignal): Promise<Answer> {
  const q = new URLSearchParams(Object.entries(query).map(([k, v]) => [k, String(v)])).toString();
  return new Promise((done, fail) => {
    const req = request(
      { socketPath: link.socket, path: `${path}?${q}`, method: "GET", headers: { authorization: `Bearer ${link.token}`, "stillfail-viewer": viewer, "accept-language": "zh-CN" }, ...(signal ? { signal } : {}) },
      (res) => {
        const parts: Buffer[] = [];
        res.on("data", (b: Buffer) => parts.push(b));
        res.on("end", () => done({ status: res.statusCode ?? 0, headers: res.headers, body: Buffer.concat(parts) }));
        res.on("error", fail);
      },
    );
    req.on("error", (e) => fail(new MediaError("station", `连不上 station：${e.message}`)));
    req.end();
  });
}

/// The station's refusal as the service's own: its status, words the member understands.
function refused(a: Answer): MediaError {
  let code = "";
  let message = "";
  try {
    const body = JSON.parse(a.body.toString("utf8")) as { code?: string; error?: string };
    code = body.code ?? "";
    message = body.error ?? "";
  } catch {}
  if (code === "not_a_root") return new MediaError("forbidden", "这个位置不在可以访问的文件夹里");
  if (a.status === 404 || code === "not_found") return new MediaError("not_found", "找不到这个文件");
  if (a.status === 403) return new MediaError("forbidden", message && /[一-鿿]/.test(message) ? message : "没有权限读取这个文件");
  if (a.status === 401) return new MediaError("station", "station 不认这个媒体服务的凭证");
  return new MediaError("station", `station 读取失败${message ? `：${message}` : ""}`);
}

async function json<T>(link: StationLink, viewer: string, path: string, query: Record<string, string>): Promise<T> {
  const a = await get(link, viewer, path, query);
  if (a.status !== 200) throw refused(a);
  return JSON.parse(a.body.toString("utf8")) as T;
}

export const stat = (link: StationLink, viewer: string, root: string, path: string) => json<DriveEntry>(link, viewer, "/drive/stat", { root, path });

export const list = (link: StationLink, viewer: string, root: string, path: string) =>
  json<{ path: string; entries: DriveEntry[]; truncated?: boolean }>(link, viewer, "/drive/list", { root, path });

/// A part of a file: its bytes, the file's whole size and time.
export async function readPart(link: StationLink, viewer: string, root: string, path: string, offset: number, length: number) {
  const a = await get(link, viewer, "/drive/read", { root, path, offset, length: Math.min(length, PART) });
  if (a.status !== 200 && a.status !== 206) throw refused(a);
  const total = Number(a.headers["stillfail-total"] ?? NaN);
  const mtime = Number(a.headers["stillfail-mtime"] ?? 0);
  return { bytes: a.body, total: Number.isFinite(total) ? total : offset + a.body.length, mtime };
}

/// A whole file, read in parts; `first` is called with the first part (to refuse a file early by its start). Refused
/// (413) above `most` bytes, and (409) when the file changes while it is read.
export async function readAll(link: StationLink, viewer: string, root: string, path: string, most: number, first?: (head: Buffer, total: number) => void): Promise<{ bytes: Buffer; mtime: number }> {
  const head = await readPart(link, viewer, root, path, 0, PART);
  first?.(head.bytes, head.total);
  if (head.total > most) throw new MediaError("too_large", `文件太大（超过 ${Math.round(most / 1024 / 1024)} MB），无法导入`);
  const parts = [head.bytes];
  let at = head.bytes.length;
  while (at < head.total) {
    const part = await readPart(link, viewer, root, path, at, Math.min(PART, head.total - at));
    if (part.total !== head.total || part.mtime !== head.mtime) throw new MediaError("conflict", "文件在导入时被修改了，请稍后再试");
    if (part.bytes.length === 0) break;
    parts.push(part.bytes);
    at += part.bytes.length;
  }
  return { bytes: Buffer.concat(parts), mtime: head.mtime };
}

/// Whether the folder changed (the station's long poll: answered at once when it did since `id` last asked, else as
/// soon as it does, else after about 25 s with false). Ends (refused) when `signal` aborts.
export async function watch(link: StationLink, viewer: string, root: string, path: string, id: string, signal?: AbortSignal): Promise<boolean> {
  const a = await get(link, viewer, "/drive/watch", { root, path, id }, signal);
  if (a.status !== 200) throw refused(a);
  return (JSON.parse(a.body.toString("utf8")) as { changed?: boolean }).changed === true;
}

/// A picture the station made of a file: its bytes and type, and (a thumbnail's) ThumbHash with the size it is of.
export type Picture = { bytes: Buffer; type: string; hash?: string; w?: number; h?: number };

/// An image's thumbnail (`/thumb`: at most 720×600; png, jpg, jpeg, webp) or a video's poster (`/poster`, a JPEG);
/// null when the station makes none of that file (its 404 without a drive refusal's code).
export async function picture(link: StationLink, viewer: string, what: "thumb" | "poster", root: string, path: string): Promise<Picture | null> {
  const a = await get(link, viewer, `/${what}`, { root, path });
  if (a.status === 404) {
    let code = "";
    try {
      code = (JSON.parse(a.body.toString("utf8")) as { code?: string }).code ?? "";
    } catch {}
    if (code === "not_found" || code === "not_a_root") throw refused(a);
    return null;
  }
  if (a.status !== 200) throw refused(a);
  const header = (k: string) => {
    const v = a.headers[k];
    return typeof v === "string" ? v : undefined;
  };
  const w = Number(header("stillfail-width"));
  const h = Number(header("stillfail-height"));
  const hash = header("stillfail-thumbhash");
  return { bytes: a.body, type: header("content-type") ?? "image/jpeg", ...(hash ? { hash } : {}), ...(w > 0 && h > 0 ? { w, h } : {}) };
}
