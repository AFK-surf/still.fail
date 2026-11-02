// The keeper's proxy (docs/vault.md, 三种用法 › 代理): a command run with a grant gets HTTPS_PROXY pointing here, with
// credentials that name its run, and the grant's placeholder (`stillfail-secret:<grant>`) where its token goes. HTTPS to
// one of the grant's hosts is opened here (with a certificate of the keeper's CA, which the command is told to trust)
// so the placeholder in the request's headers can be replaced with the secret on its way out; nothing else of the
// request or the answer is touched. HTTPS to any other host is passed through as it is, unopened: a placeholder sent
// there is only a placeholder. Plain HTTP is refused, so the secret never goes out unencrypted.
import { type KeyObject, createPrivateKey, randomBytes, timingSafeEqual } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { type IncomingMessage, type Server, type ServerResponse, createServer } from "node:http";
import { type RequestOptions, request as httpsRequest } from "node:https";
import { type Socket, connect } from "node:net";
import { join } from "node:path";
import { type SecureContext, TLSSocket, createSecureContext, rootCertificates } from "node:tls";
import { hostAllowed } from "./keeper.ts";
import { makeCa, makeLeaf, pem } from "./x509.ts";

/// What stands for a grant's secret in what a command sends.
export const placeholder = (grant: string) => `stillfail-secret:${grant}`;

/// A command's run through the proxy: the hosts its secret may go to, the placeholder and the value it stands for, and
/// what is told each time it is put in (the host).
export type Run = { hosts: string[]; placeholder: string; value: string; used: (host: string) => void; allowed?: () => boolean };

const CA_NAME = "still.fail station vault";
/// Leaf certificates are made again a day before the week they are good for runs out.
const LEAF_MS = 6 * 86400_000;
const HOP = ["proxy-authorization", "proxy-connection", "connection", "keep-alive", "te", "trailer", "transfer-encoding", "upgrade"];

/// `text` with the placeholder replaced by the value, also inside an `Authorization: Basic` pair.
export function swap(text: string, run: Pick<Run, "placeholder" | "value">): string {
  const basic = /^(Basic\s+)([A-Za-z0-9+/=]+)$/i.exec(text);
  if (basic) {
    const pair = Buffer.from(basic[2]!, "base64").toString("utf8");
    if (pair.includes(run.placeholder)) return `${basic[1]}${Buffer.from(pair.split(run.placeholder).join(run.value), "utf8").toString("base64")}`;
  }
  return text.split(run.placeholder).join(run.value);
}

export class Proxy {
  readonly #dir: string;
  readonly #now: () => number;
  readonly #runs = new Map<string, Run>();
  readonly #leaves = new Map<string, { context: SecureContext; made: number }>();
  #ca: { cert: Buffer; key: KeyObject } | null = null;
  #server: Server | null = null;
  #port = 0;
  /// The roots the hosts' own certificates are checked against: Node's by default (a test's own).
  readonly #trust: string[] | undefined;

  /// `dir`: where the CA is kept (made there the first time); `now`: milliseconds.
  constructor(dir: string, now: () => number, trust?: string[]) {
    this.#dir = dir;
    this.#now = now;
    this.#trust = trust;
  }

  /// The CA bundle a command is told to trust: the usual roots and the keeper's CA.
  get bundle(): string {
    return join(this.#dir, "ca-bundle.pem");
  }

  #loadCa(): { cert: Buffer; key: KeyObject } {
    if (this.#ca !== null) return this.#ca;
    mkdirSync(this.#dir, { recursive: true, mode: 0o700 });
    const keyPath = join(this.#dir, "ca.key");
    const certPath = join(this.#dir, "ca.pem");
    if (existsSync(keyPath) && existsSync(certPath)) {
      const der = Buffer.from(readFileSync(certPath, "utf8").replace(/-----[^-]+-----|\s+/g, ""), "base64");
      this.#ca = { cert: der, key: createPrivateKey(readFileSync(keyPath)) };
    } else {
      this.#ca = makeCa(this.#now(), CA_NAME);
      writeFileSync(keyPath, this.#ca.key.export({ format: "pem", type: "pkcs8" }), { mode: 0o600 });
      chmodSync(keyPath, 0o600);
      writeFileSync(certPath, pem(this.#ca.cert));
    }
    writeFileSync(this.bundle, [...rootCertificates, pem(this.#ca.cert)].join("\n"));
    return this.#ca;
  }

  /// Listens on 127.0.0.1 (any free port); the port.
  async start(): Promise<number> {
    if (this.#server !== null) return this.#port;
    this.#loadCa();
    const server = createServer((_req, res) => res.writeHead(405, { "content-type": "text/plain" }).end("the vault's proxy carries HTTPS only (CONNECT)\n"));
    server.on("connect", (req: IncomingMessage, socket: Socket, head: Buffer) => this.#connect(req, socket, head));
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", () => resolve());
    });
    this.#server = server;
    this.#port = (server.address() as { port: number }).port;
    return this.#port;
  }

  close() {
    this.#server?.close();
    this.#server?.closeAllConnections();
    this.#server = null;
  }

  /// Lets `run` through: the proxy URL a command uses (its credentials name the run), and a function that ends it.
  admit(run: Run): { url: string; end: () => void } {
    const token = randomBytes(24).toString("base64url");
    this.#runs.set(token, run);
    return { url: `http://run:${token}@127.0.0.1:${this.#port}`, end: () => this.#runs.delete(token) };
  }

  /// The run a CONNECT's credentials name, if any.
  #runOf(req: IncomingMessage): Run | null {
    const basic = /^Basic\s+(.+)$/i.exec(req.headers["proxy-authorization"] ?? "");
    if (!basic) return null;
    const pair = Buffer.from(basic[1]!, "base64").toString("utf8");
    const given = Buffer.from(pair.slice(pair.indexOf(":") + 1));
    for (const [token, run] of this.#runs) {
      const t = Buffer.from(token);
      if (t.length === given.length && timingSafeEqual(t, given)) return run;
    }
    return null;
  }

  #connect(req: IncomingMessage, socket: Socket, head: Buffer) {
    socket.on("error", () => socket.destroy());
    const run = this.#runOf(req);
    const target = /^\[?([^\]]+?)\]?:(\d+)$/.exec(req.url ?? "");
    if (run === null || target === null) {
      socket.end(`HTTP/1.1 ${run === null ? "407 Proxy Authentication Required" : "400 Bad Request"}\r\n\r\n`);
      return;
    }
    const host = target[1]!.toLowerCase();
    const port = Number(target[2]);
    if (!hostAllowed(host, run.hosts)) return this.#tunnel(socket, head, host, port);
    socket.write("HTTP/1.1 200 Connection Established\r\n\r\n");
    if (head.length > 0) socket.unshift(head);
    const tls = new TLSSocket(socket, { isServer: true, secureContext: this.#leaf(host), ALPNProtocols: ["http/1.1"] });
    tls.on("error", () => tls.destroy());
    const inner = createServer((r, res) => this.#forward(r, res, host, port, run));
    inner.on("clientError", (_e, s) => s.destroy());
    inner.emit("connection", tls);
  }

  /// HTTPS to a host the grant is not for: carried as it is.
  #tunnel(socket: Socket, head: Buffer, host: string, port: number) {
    const upstream = connect(port, host, () => {
      socket.write("HTTP/1.1 200 Connection Established\r\n\r\n");
      if (head.length > 0) upstream.write(head);
      upstream.pipe(socket);
      socket.pipe(upstream);
    });
    upstream.on("error", () => socket.end("HTTP/1.1 502 Bad Gateway\r\n\r\n"));
    socket.on("close", () => upstream.destroy());
  }

  /// One request inside an opened HTTPS connection: sent on with the placeholder swapped in its headers.
  #forward(req: IncomingMessage, res: ServerResponse, host: string, port: number, run: Run) {
    if (run.allowed?.() === false) { res.writeHead(403).end("grant expired"); return; }
    const headers: Record<string, string | string[]> = {};
    let swapped = false;
    for (const [name, value] of Object.entries(req.headers)) {
      if (value === undefined || HOP.includes(name)) continue;
      const put = (v: string) => {
        const s = swap(v, run);
        if (s !== v) swapped = true;
        return s;
      };
      headers[name] = Array.isArray(value) ? value.map(put) : put(value);
    }
    headers.host = port === 443 ? host : `${host}:${port}`;
    if (swapped) run.used(host);
    const options: RequestOptions = { host, port, servername: host, method: req.method, path: req.url, headers, ...(this.#trust ? { ca: this.#trust } : {}) };
    const out = httpsRequest(options, (answer) => {
      const back: Record<string, string | string[]> = {};
      for (const [name, value] of Object.entries(answer.headers)) if (value !== undefined && !HOP.includes(name)) back[name] = value;
      if (answer.statusMessage) res.statusMessage = answer.statusMessage;
      res.writeHead(answer.statusCode ?? 502, back);
      answer.pipe(res);
    });
    out.on("error", (e) => {
      if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" }).end(`the vault's proxy could not reach ${host}: ${e.message}\n`);
      else res.destroy();
    });
    req.pipe(out);
  }

  /// The TLS context shown for `host`, its certificate made when there is none or it is about to run out.
  #leaf(host: string): SecureContext {
    const had = this.#leaves.get(host);
    const now = this.#now();
    if (had !== undefined && now - had.made < LEAF_MS) return had.context;
    const leaf = makeLeaf(this.#loadCa(), CA_NAME, host, now);
    const context = createSecureContext({ key: leaf.key.export({ format: "pem", type: "pkcs8" }), cert: pem(leaf.cert) + pem(this.#loadCa().cert) });
    this.#leaves.set(host, { context, made: now });
    return context;
  }
}
