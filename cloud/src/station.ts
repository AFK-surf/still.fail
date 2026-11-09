// One station's own object, named by its key (hex): its presence socket (hibernatable, so an idle one costs nothing),
// and whether it is enrolled, which every request it signs asks (tracing.ts stationSender). What it is told (where it
// is, its peers, what is revoked: the `state` frame) stays the Directory's: this object reads it there as the socket
// opens and as the Directory tells it it changed (directory.ts #deliver), and keeps nothing of it but that the station
// is enrolled. Whether a station is up is not the cloud's to say: devices find it out over the mesh.
import { DurableObject } from "cloudflare:workers";
import { header } from "./compat";
import { CLOSE, SILENT_MS, sockets, type Delivery } from "./directory";
import type { Env } from "./env";

/** `gen`: as the Directory counted this socket's opening (stationConnected), said back as it closes. */
type Attachment = { station: string; at: number; gen: number; dropped?: boolean };

export class Station extends DurableObject<Env> {
  /** Sockets opening now, and whether it was told something meanwhile (what it read as it opened may be older). */
  #opening = 0;
  #toldMeanwhile = false;
  /** How many times it was let go while this object lives: an answer read before one is not kept after it. */
  #letGo = 0;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    if (sockets.where(env) === "primary") this.handBack();
  }

  /** Rolled back (directory.ts `sockets`): its socket closed as a restarting service's, so it reconnects onto the Directory. */
  protected handBack(): void {
    for (const ws of this.#open()) this.#drop(ws, 1012, "moved");
  }

  #directory() {
    return this.env.DIRECTORY.getByName("primary");
  }

  /** Whether the station is enrolled (in some workspace): asked of the Directory once, kept until it is let go. */
  async isStation(station: string): Promise<boolean> {
    if (this.ctx.storage.kv.get("enrolled")) return true;
    const before = this.#letGo;
    const enrolled = await this.#directory().isStation(station);
    if (enrolled && before === this.#letGo) this.ctx.storage.kv.put("enrolled", true);
    return enrolled;
  }

  /**
   * The presence socket, which the Worker authenticated (`x-stillfail-station`, whose signature it checked; its
   * version in `x-stillfail-version`). One per station: a reconnect replaces the one it gave up on.
   */
  async fetch(request: Request): Promise<Response> {
    const station = header(request, "station")!;
    const before = this.#letGo;
    this.#opening++;
    let said: { frame: string | null; gen: number };
    try {
      if (this.#opening === 1) this.#toldMeanwhile = false;
      said = await this.#directory().stationConnected(station, header(request, "version"));
    } finally {
      this.#opening--;
    }
    if (said.frame === null) {
      this.#gone();
      return Response.json({ error: "station_removed" }, { status: 404 });
    }
    if (before === this.#letGo) this.ctx.storage.kv.put("enrolled", true);
    for (const old of this.#open()) this.#drop(old, CLOSE.replaced, "replaced");
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ station, at: Date.now(), gen: said.gen } satisfies Attachment);
    pair[1].send(said.frame);
    if (this.#toldMeanwhile) await this.#sendState(station);
    if ((await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + SILENT_MS); // timer: a heartbeat's check, the station's pings
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  /** What the Directory tells it (directory.ts #deliver): sent on its socket; whether it holds one. */
  async deliver(station: string, body: Delivery): Promise<{ live: boolean }> {
    if (this.#opening > 0) this.#toldMeanwhile = true;
    if (body.state && !(await this.#sendState(station))) return { live: false };
    for (const frame of body.frames ?? []) this.#send(frame);
    return { live: this.#open().length > 0 };
  }

  /** Its state as the Directory has it now, sent; in no workspace now, it is let go (false). */
  async #sendState(station: string): Promise<boolean> {
    const frame = await this.#directory().stationState(station);
    if (frame === null) {
      this.#gone();
      return false;
    }
    this.#send(frame);
    return true;
  }

  /** In no workspace: no longer a station, its socket closed for good (4004: it stops reconnecting). */
  #gone(): void {
    this.#letGo++;
    this.ctx.storage.kv.delete("enrolled");
    for (const ws of this.#open()) this.#drop(ws, CLOSE.removed, "station_removed");
  }

  #send(frame: string): void {
    for (const ws of this.#open()) {
      try {
        ws.send(frame);
      } catch {
        // Closing already: it hears all of it when it connects again.
      }
    }
  }

  /** The open presence sockets (at most one, but a replaced one may linger). */
  #open(): WebSocket[] {
    return this.ctx.getWebSockets().filter((ws) => ws.readyState === WebSocket.OPEN && !(ws.deserializeAttachment() as Attachment).dropped);
  }

  /** Closes a socket from this side; its close event then changes nothing. */
  #drop(ws: WebSocket, code: number, reason: string): void {
    ws.serializeAttachment({ ...(ws.deserializeAttachment() as Attachment), dropped: true });
    try {
      ws.close(code, reason);
    } catch {
      // Already closed.
    }
  }

  /** "ping" is answered by the runtime; what else a station says is of the workspace locks, answered by the Directory. */
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    const { station } = ws.deserializeAttachment() as Attachment;
    for (const frame of await this.#directory().stationSaid(station, message)) ws.send(frame);
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code);
    } catch {
      // The runtime completed the close.
    }
    await this.#left(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.#left(ws);
  }

  /** A socket gone that this side did not close: when the station was last here, and it holds none now. */
  async #left(ws: WebSocket): Promise<void> {
    const { station, gen, dropped } = ws.deserializeAttachment() as Attachment;
    if (!dropped) await this.#directory().stationLeft(station, gen);
  }

  // A station that vanishes without closing (power cut, network gone) can leave a socket the runtime keeps for a long
  // time. It sends "ping" every PING_SEC and the runtime answers without waking this object, noting when; while its
  // socket is open an alarm looks at that every SILENT_MS and drops it when silent, so when it was last here (the
  // console's and the app's last seen) is when it went, not when the runtime happened to notice.
  async alarm(): Promise<void> {
    if (await this.sweep(Date.now())) await this.ctx.storage.setAlarm(Date.now() + SILENT_MS); // timer: a heartbeat's check, the station's pings
  }

  /** Drops its socket if silent at `now`; says whether it is still connected. */
  protected async sweep(now: number): Promise<boolean> {
    let connected = false;
    for (const ws of this.#open()) {
      const attachment = ws.deserializeAttachment() as Attachment;
      const answered = this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? 0;
      if (now - Math.max(attachment.at, answered) > SILENT_MS) {
        this.#drop(ws, CLOSE.silent, "silent");
        await this.#directory().stationLeft(attachment.station, attachment.gen);
      } else connected = true;
    }
    return connected;
  }
}
