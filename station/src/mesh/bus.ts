// The station's requests to and from the other stations of its workspace (the station transport, `stillfail/station/2`,
// mesh/peer.ts): one bus for every part that asks or answers them. A part says which methods it answers (`on`); a
// request is answered by the part whose method or prefix (`share.`) it names, a request of a station of another
// workspace by the one that hears those (`outside`). What is asked before the mesh is up waits for it (MESH_WAIT_MS).
import type { Json } from "../store/store.ts";

/// The answer of a peer that refused a request (its `{"error": …}`): final, unlike a request that did not get through.
export class Refused extends Error {}

/// Bytes that follow a request's or an answer's head on its stream (`stillfail/station/2`, mesh/peer.ts): a file as it
/// is read, at the pace the other end takes it. A request or an answer carries them under this symbol, so they go
/// along with it through every part that hands it on, and never into its JSON. A request's are read by the part that
/// answers it, all of them; an answer's by whoever asked, all of them or until it stops reading (`return`). A request
/// for a file says `whole: true` to have it all after the answer; a transport that carries no bytes takes that out, and
/// the file is answered a chunk at a time, as stations from before answer.
export const BYTES = Symbol("bytes");
export type Bytes = AsyncIterable<Buffer>;

/// The bytes `json` carries, if any.
export const bytesOf = (json: Json): Bytes | null => (json !== null && typeof json === "object" && (json[BYTES] as Bytes | undefined)) || null;

/// `json` with `bytes` after it.
export const withBytes = <T extends object>(json: T, bytes: Bytes): T => Object.assign(json, { [BYTES]: bytes });

/// A request with bytes to a station whose transport carries none (`stillfail/station/1`, before 2026-10-29): not
/// sent; its caller sends them as it did then, in chunks.
export class NoBytes extends Error {}

/// A request to another station of the workspace over the station transport: its result, a Refused when that station
/// answered with an error, any other error when it could not be asked (or the answer did not come). `workspace` is the
/// request's (null for `peers` and `describe`, which the transport answers or checks against its own). Station "" with
/// method `peers` is the transport's roster: {workspace, stations, current}.
export type PeerCall = (station: string, workspace: string | null, request: Json) => Promise<Json>;
/// Takes a request another station sent here: from which station, the request. `workspace`: which of this station's
/// workspaces the request was made in, when the transport knows it.
export type Inbox = (peer: string, request: Json, workspace?: string) => Promise<Json>;

/// A request asked before the transport is attached (a chat taken up as the station starts, its subscription borrowed
/// from another station) waits for it this long: the mesh is up within a second, or ~15 s when it waits for a relay
/// (mesh/mesh.ts), before it is attached.
export const MESH_WAIT_MS = 30_000;

const methodOf = (request: Json): string => (request !== null && typeof request === "object" && typeof request.method === "string" ? request.method : "");

export class PeerBus {
  private call: PeerCall | null = null;
  private attached: Promise<void>;
  private markAttached!: () => void;
  private readonly waitMs: number;
  private readonly sleep: (ms: number) => Promise<void>;
  /// What answers which method: a whole method's name, or a prefix ending in `.`.
  private readonly handlers = new Map<string, Inbox>();
  /// What answers the methods none names (the remote tasks).
  private rest: Inbox | null = null;
  private outsider: Inbox | null = null;
  private readonly onAttach: (() => void)[] = [];

  /// `sleep`: how a request waits for the transport (the station's clock).
  constructor(options: { waitMs?: number; sleep: (ms: number) => Promise<void> }) {
    this.waitMs = options.waitMs ?? MESH_WAIT_MS;
    this.sleep = options.sleep;
    this.attached = new Promise((resolve) => (this.markAttached = resolve));
  }

  /// The transport is there (mesh/mesh.ts): what waited for it is asked, what follows it starts.
  attach(call: PeerCall): void {
    this.call = call;
    this.markAttached();
    for (const f of this.onAttach.splice(0)) f();
  }

  /// `f` once the transport is there (at once if it is).
  whenAttached(f: () => void): void {
    if (this.call) f();
    else this.onAttach.push(f);
  }

  /// A request to another station of the workspace.
  async ask(station: string, request: Json): Promise<Json> {
    if (!this.call) await Promise.race([this.attached, this.sleep(this.waitMs)]);
    const call = this.call;
    if (!call) throw new Error("station mesh is not ready");
    const workspace = typeof request?.workspace === "string" ? request.workspace : null;
    return call(station, workspace, request);
  }

  /// Who answers `methods` (whole names, or prefixes ending in `.`): one part each.
  on(methods: string | string[], inbox: Inbox): void {
    for (const method of Array.isArray(methods) ? methods : [methods]) this.handlers.set(method, inbox);
  }

  /// Who answers what no other part does.
  otherwise(inbox: Inbox): void {
    this.rest = inbox;
  }

  /// Who answers stations of other workspaces (chats shared across workspaces, xshare/index.ts).
  outside(inbox: Inbox): void {
    this.outsider = inbox;
  }

  /// Whether stations of other workspaces are heard at all.
  hearsOutside(): boolean {
    return this.outsider !== null;
  }

  /// A request of a station of `workspace` (the transport authenticated it and checked it belongs).
  handle(workspace: string, peer: string, request: Json): Promise<Json> {
    const method = methodOf(request);
    const dot = method.indexOf(".");
    const inbox = this.handlers.get(method) ?? (dot > 0 ? this.handlers.get(method.slice(0, dot + 1)) : undefined) ?? this.rest;
    if (!inbox) return Promise.reject(new Error("station is starting"));
    return inbox(peer, request, workspace);
  }

  /// A request of a station that is not of this workspace (the transport checked it names this workspace).
  handleOutside(peer: string, request: Json, workspace?: string): Promise<Json> {
    const outsider = this.outsider;
    if (!outsider) return Promise.reject(new Error("station is starting"));
    return outsider(peer, request, workspace);
  }
}
