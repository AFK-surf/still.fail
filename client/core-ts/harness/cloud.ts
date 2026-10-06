// A still.fail cloud for the side-by-side runs (docs/core-ts.md, 怎么验证): the account API the client core uses, over
// real HTTP and a real `/v1/events` WebSocket, answering both cores alike. Its state is plain data, so a script can
// change it between steps and push events as the real cloud would.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { FakeStation } from "./station.ts";

export type User = { sub: string; email: string; name: string; picture: string; beta?: boolean };
export type Workspace = { id: string; name: string; role: string; created_at: number; members: unknown[]; stations: Station[]; invitations: unknown[] };
export type Station = { id: string; name: string; online: boolean; last_seen: number | null; version: string; created_at: number };

/// Every time the cloud says, at a fixed point (seconds): the same for both cores' runs.
export const T0 = 1_790_000_000;

export class FakeCloud {
  readonly users = new Map<string, User>();
  /// Access and refresh tokens → sub.
  readonly tokens = new Map<string, string>();
  /// Sign-in codes → sub.
  readonly codes = new Map<string, string>();
  readonly workspaces = new Map<string, Workspace>();
  /// Who is in which workspace.
  readonly members = new Map<string, Set<string>>();
  readonly invitations: { id: string; workspace: string; email: string; role: string }[] = [];
  readonly sessions = new Map<string, { id: string; name: string; current: boolean; created_at: number }[]>();
  readonly sockets = new Set<{ sub: string; ws: WebSocket }>();
  /// What was asked, `METHOD path`, in order.
  readonly log: string[] = [];
  #server: Server | null = null;
  #wss: WebSocketServer | null = null;
  #next = 1;
  #opening: (() => void)[] = [];
  /// Answer pings with pong (a cloud from before them does not).
  pongs = true;
  /// Every station of every workspace, answering at this origin (harness/station.ts).
  readonly station: FakeStation;

  constructor(station = new FakeStation()) {
    this.station = station;
    this.addUser({ sub: "u-alice", email: "alice@x.test", name: "Alice", picture: "https://pic.test/alice" });
    this.addUser({ sub: "u-bob", email: "bob@x.test", name: "Bob", picture: "" });
    this.codes.set("code-alice", "u-alice");
    this.codes.set("code-bob", "u-bob");
    const ws = this.addWorkspace("ws1", "研发", "u-alice");
    ws.stations.push({ id: "st1", name: "studio", online: true, last_seen: T0 - 30, version: "0.1.900", created_at: T0 - 86400 * 3 });
    ws.stations.push({ id: "st2", name: "mini", online: false, last_seen: T0 - 7200, version: "0.1.880", created_at: T0 - 86400 * 20 });
    this.members.get("ws1")!.add("u-bob");
    this.addWorkspace("ws2", "个人", "u-bob");
    this.sessions.set("u-alice", [{ id: "d1", name: "still.fail 网页版", current: true, created_at: T0 - 600 }]);
  }

  addUser(user: User): void {
    this.users.set(user.sub, user);
  }

  addWorkspace(id: string, name: string, owner: string): Workspace {
    const ws: Workspace = { id, name, role: "owner", created_at: T0 - 86400 * 30, members: [], stations: [], invitations: [] };
    this.workspaces.set(id, ws);
    this.members.set(id, new Set([owner]));
    return ws;
  }

  #me(sub: string): unknown {
    const user = this.users.get(sub)!;
    const workspaces = [...this.workspaces.values()]
      .filter((w) => this.members.get(w.id)?.has(sub))
      .map((w) => ({ id: w.id, name: w.name, role: [...this.members.get(w.id)!][0] === sub ? "owner" : "member", created_at: w.created_at }));
    const invitations = this.invitations.filter((i) => i.email === user.email).map((i) => ({ id: i.id, workspace: { id: i.workspace, name: this.workspaces.get(i.workspace)?.name }, role: i.role }));
    // No relay: a run has no mesh, and both cores leave it alone.
    return { user: { sub, email: user.email, name: user.name, picture: user.picture, beta: user.beta ?? false }, workspaces, invitations, relay_url: null };
  }

  #workspace(id: string): unknown {
    const w = this.workspaces.get(id)!;
    const members = [...this.members.get(id)!].map((sub, i) => {
      const u = this.users.get(sub)!;
      return { sub, email: u.email, name: u.name, role: i === 0 ? "owner" : "member", joined_at: w.created_at + i * 60 };
    });
    return { id, name: w.name, created_at: w.created_at, members, stations: w.stations, invitations: this.invitations.filter((i) => i.workspace === id) };
  }

  /// Tells every socket of `sub` (or every socket) an event, as the cloud's directory does.
  push(event: unknown, sub?: string): void {
    for (const s of this.sockets) if (sub === undefined || s.sub === sub) s.ws.send(JSON.stringify(event));
  }

  issue(sub: string): { access_token: string; refresh_token: string; subject: string; email: string; name: string; expires_at: number } {
    const n = this.#next++;
    const access = `acc-${sub}-${n}`;
    const refresh = `ref-${sub}-${n}`;
    this.tokens.set(access, sub);
    this.tokens.set(refresh, sub);
    const u = this.users.get(sub)!;
    return { access_token: access, refresh_token: refresh, subject: sub, email: u.email, name: u.name, expires_at: Math.floor(Date.now() / 1000) + 86400 };
  }

  async #handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(c as Buffer);
    const raw = Buffer.concat(chunks).toString();
    const body = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
    const url = new URL(req.url ?? "/", "http://x");
    const path = url.pathname;
    const method = req.method ?? "GET";
    this.log.push(`${method} ${path}`);
    if (this.station.handle(req, res, url, body)) return;
    const send = (status: number, value: unknown) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify(value));
    };
    const bearer = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    const sub = this.tokens.get(bearer);
    if (path === "/v1/auth/token" && method === "POST") {
      const who = this.codes.get(String(body.code));
      return who ? send(200, this.issue(who)) : send(400, { error: "invalid_grant" });
    }
    if (path === "/v1/auth/refresh") return sub ? send(200, this.issue(sub)) : send(401, { error: "invalid_session" });
    if (path === "/v1/auth/logout") return send(200, { ok: true });
    if (path === "/v1/push/key") return send(200, { vapid: "BTestVapidKey" });
    if (path === "/v1/telemetry/traces") return send(202, {});
    if (!sub) return send(401, { error: "invalid_session" });
    if (path === "/v1/me") return send(200, this.#me(sub));
    if (path === "/v1/auth/sessions") return send(200, { sessions: this.sessions.get(sub) ?? [] });
    let m = /^\/v1\/auth\/sessions\/([^/]+)$/.exec(path);
    if (m && method === "DELETE") {
      this.sessions.set(sub, (this.sessions.get(sub) ?? []).filter((s) => s.id !== m![1]));
      return send(200, { ok: true });
    }
    if (path === "/v1/workspaces" && method === "POST") {
      const name = String(body.name ?? "").trim();
      if (!name) return send(400, { error: "invalid_name" });
      const id = `ws-new-${this.#next++}`;
      this.addWorkspace(id, name, sub);
      this.push({ type: "workspaces" }, sub);
      return send(200, this.#workspace(id));
    }
    m = /^\/v1\/workspaces\/([^/]+)(\/.*)?$/.exec(path);
    if (m) {
      const id = decodeURIComponent(m[1]);
      const rest = m[2] ?? "";
      const w = this.workspaces.get(id);
      if (!w || !this.members.get(id)!.has(sub)) return send(404, { error: "workspace_not_found" });
      const owner = [...this.members.get(id)!][0] === sub;
      if (rest === "" && method === "GET") return send(200, this.#workspace(id));
      if (rest === "" && method === "PATCH") {
        if (!owner) return send(403, { error: "forbidden" });
        const name = String(body.name ?? "").trim();
        if (!name) return send(400, { error: "invalid_name" });
        w.name = name;
        for (const member of this.members.get(id)!) this.push({ type: "workspaces" }, member);
        this.push({ type: "workspace", id });
        return send(200, this.#workspace(id));
      }
      if (rest === "" && method === "DELETE") {
        if (!owner) return send(403, { error: "forbidden" });
        const members = [...this.members.get(id)!];
        this.workspaces.delete(id);
        this.members.delete(id);
        for (const member of members) this.push({ type: "workspaces" }, member);
        return send(200, { ok: true });
      }
      if (rest === "/invitations" && method === "POST") {
        if (!owner) return send(403, { error: "forbidden" });
        const email = String(body.email ?? "");
        if (!email.includes("@")) return send(400, { error: "invalid_email" });
        const inv = { id: `inv-${this.#next++}`, workspace: id, email, role: String(body.role ?? "member") };
        this.invitations.push(inv);
        this.push({ type: "workspace", id });
        return send(200, inv);
      }
      const st = /^\/stations\/([^/]+)$/.exec(rest);
      if (st && method === "PATCH") {
        const station = w.stations.find((s) => s.id === st[1]);
        if (!station) return send(404, { error: "station_not_found" });
        station.name = String(body.name ?? station.name);
        this.push({ type: "workspace", id });
        return send(200, station);
      }
      if (st && method === "DELETE") {
        w.stations = w.stations.filter((s) => s.id !== st[1]);
        this.push({ type: "workspace", id });
        return send(200, { ok: true });
      }
      const mem = /^\/members\/([^/]+)$/.exec(rest);
      if (mem && method === "DELETE") {
        const who = [...this.users.values()].find((u) => u.email === decodeURIComponent(mem[1]))?.sub;
        if (!who || !this.members.get(id)!.has(who)) return send(404, { error: "member_not_found" });
        this.members.get(id)!.delete(who);
        this.push({ type: "workspaces" }, who);
        this.push({ type: "workspace", id });
        return send(200, { ok: true });
      }
      return send(404, { error: "not_found" });
    }
    m = /^\/v1\/invitations\/([^/]+)\/(accept|decline)$/.exec(path);
    if (m && method === "POST") {
      const inv = this.invitations.find((i) => i.id === m![1]);
      if (!inv) return send(404, { error: "invitation_not_found" });
      if (this.users.get(sub)!.email !== inv.email) return send(403, { error: "invitation_for_other_email" });
      this.invitations.splice(this.invitations.indexOf(inv), 1);
      if (m[2] === "accept") this.members.get(inv.workspace)!.add(sub);
      this.push({ type: "workspaces" }, sub);
      this.push({ type: "workspace", id: inv.workspace });
      return send(200, { ok: true });
    }
    if (path === "/v1/admin/me") return send(403, { error: "forbidden" });
    return send(404, { error: "not_found" });
  }

  listen(port: number): Promise<void> {
    this.#server = createServer((req, res) => {
      this.#handle(req, res).catch((e) => {
        res.writeHead(500);
        res.end(String(e));
      });
    });
    this.#wss = new WebSocketServer({
      noServer: true,
      handleProtocols: (protocols) => (protocols.has("stillfail-events") ? "stillfail-events" : false),
    });
    this.#server.on("upgrade", (req, socket, head) => {
      const protocols = String(req.headers["sec-websocket-protocol"] ?? "").split(",").map((p) => p.trim());
      const token = protocols.find((p) => p.startsWith("stillfail-token."))?.slice("stillfail-token.".length) ?? "";
      const sub = this.tokens.get(token);
      this.log.push(`WS /v1/events${sub ? "" : " (refused)"}`);
      if (!sub) {
        socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
        socket.destroy();
        return;
      }
      this.#wss!.handleUpgrade(req, socket, head, (ws) => {
        const entry = { sub, ws };
        this.sockets.add(entry);
        for (const wake of this.#opening.splice(0)) wake();
        ws.on("message", (data) => {
          if (data.toString() === "ping" && this.pongs) ws.send("pong");
        });
        ws.on("close", () => this.sockets.delete(entry));
      });
    });
    return new Promise((resolve) => this.#server!.listen(port, "127.0.0.1", () => resolve()));
  }

  /// Once an events socket is open: now, or when the next one opens.
  socketOpen(): Promise<void> {
    return this.sockets.size ? Promise.resolve() : new Promise((resolve) => this.#opening.push(resolve));
  }

  /// The port it listens on (`listen(0)`: one the system chose).
  port(): number {
    return (this.#server!.address() as { port: number }).port;
  }

  close(): Promise<void> {
    this.station.close();
    for (const s of this.sockets) s.ws.terminate();
    this.#wss?.close();
    return new Promise((resolve) => (this.#server ? this.#server.close(() => resolve()) : resolve()));
  }
}
