// Reaching a station from the browser: this browser's iroh endpoint (its
// device key, kept in localStorage) and a link per station, opened with a
// grant from ember cloud and renewed before the grant runs out. The admin
// client talks through it via the Transport interface.
import { cloud } from "./api.ts";
import { sseParser, type Transport } from "../transport.ts";
import type { Link, Mesh } from "../mesh/pkg/ember_mesh_web.js";

const DEVICE = "ember.device";
let mesh: Promise<Mesh> | null = null;

/** This browser's endpoint; one per page, whichever account or station. */
export function device(relayUrl: string): Promise<Mesh> {
  mesh ??= (async () => {
    const wasm = await import("../mesh/pkg/ember_mesh_web.js");
    await wasm.default();
    const stored = localStorage.getItem(DEVICE);
    const secret = stored ? Uint8Array.from(atob(stored), (c) => c.charCodeAt(0)) : new Uint8Array();
    const created = await wasm.Mesh.create(secret, relayUrl);
    if (!stored) localStorage.setItem(DEVICE, btoa(String.fromCharCode(...created.secret())));
    return created;
  })();
  mesh.catch(() => { mesh = null; });
  return mesh;
}

const RENEW_MS = 5 * 60_000;

export class StationTransport implements Transport {
  readonly #sub: string;
  readonly #workspace: string;
  readonly #station: string;
  readonly #relay: string;
  #link: Promise<Link> | null = null;
  #renew: ReturnType<typeof setInterval> | null = null;

  constructor(sub: string, workspace: string, station: string, relayUrl: string) {
    this.#sub = sub;
    this.#workspace = workspace;
    this.#station = station;
    this.#relay = relayUrl;
  }

  /** The open link, reconnecting (with a fresh grant) if it closed. */
  async #open(): Promise<Link> {
    if (this.#link) {
      const link = await this.#link.catch(() => null);
      if (link && !link.closed()) return link;
      this.#link = null;
    }
    this.#link = (async () => {
      const endpoint = await device(this.#relay);
      const grant = await cloud.grant(this.#sub, this.#workspace, this.#station, endpoint.id());
      const link = await endpoint.connect(this.#station, grant.relay_url, grant.grant) as Link;
      if (this.#renew) clearInterval(this.#renew);
      this.#renew = setInterval(() => void this.#renewGrant(link), RENEW_MS);
      return link;
    })();
    this.#link.catch(() => { this.#link = null; });
    return this.#link;
  }

  async #renewGrant(link: Link): Promise<void> {
    try {
      const endpoint = await device(this.#relay);
      const grant = await cloud.grant(this.#sub, this.#workspace, this.#station, endpoint.id());
      await link.renew(grant.grant);
    } catch {
      // Removed from the workspace, or offline: the next request reconnects or reports it.
      this.#link = null;
    }
  }

  async #send(method: string, path: string, body?: unknown) {
    const link = await this.#open();
    const head = JSON.stringify({ method, path: `/admin/api${path}`, headers: body === undefined ? {} : { "content-type": "application/json" } });
    const reply = await link.request(head, body === undefined ? new Uint8Array() : new TextEncoder().encode(JSON.stringify(body)));
    return { reply, head: JSON.parse(reply.head()) as { status: number; headers: Record<string, string> } };
  }

  async request(method: string, path: string, body?: unknown) {
    const { reply, head } = await this.#send(method, path, body);
    const decoder = new TextDecoder();
    let text = "";
    for (let chunk = await reply.next(); chunk; chunk = await reply.next()) text += decoder.decode(chunk, { stream: true });
    let data: unknown = {};
    try {
      data = JSON.parse(text);
    } catch {
      // not JSON: leave empty
    }
    return { status: head.status, data };
  }

  events(onEvent: (name: string, data: string) => void, onOpen: () => void): () => void {
    let stopped = false;
    let current: { cancel(): void } | null = null;
    void (async () => {
      while (!stopped) {
        try {
          const { reply } = await this.#send("GET", "/events");
          current = reply;
          onOpen();
          const feed = sseParser(onEvent);
          const decoder = new TextDecoder();
          for (let chunk = await reply.next(); chunk && !stopped; chunk = await reply.next()) feed(decoder.decode(chunk, { stream: true }));
        } catch {
          // fall through to retry
        }
        if (!stopped) await new Promise((r) => setTimeout(r, 3000));
      }
    })();
    return () => {
      stopped = true;
      current?.cancel();
    };
  }

  close(): void {
    if (this.#renew) clearInterval(this.#renew);
    void this.#link?.then((l) => l.close()).catch(() => undefined);
  }
}
