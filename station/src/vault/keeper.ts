// What the station holds of the secrets agents use (docs/vault.md, keeper): for each request still waiting, the private
// half of the box its secret is to be sealed to; for each grant, the opened secret, until it is used up or runs out.
// Only in memory: nothing here is written to disk or logged, and a restart forgets it all (the agent asks again).
// Whether a grant may be taken is decided here, from the grant itself: who signed it (a member of the vault, by a
// device in the lock), that it answers the request as asked, and that it stays within what the item allows.
import type { LockState } from "../cloud/lock.ts";
import { type Grant, type Item, type Mode, type Request, type Scope, type Vault, TAG, grantContext, newBoxPair, openSeal, signedOk, signerOf } from "./crypto.ts";

/// The longest a grant may last, by its scope (seconds), with a minute's slack for the clocks of phone and station.
const LASTS: Record<Scope, number> = { once: 3600, hour: 3600, chat: 86400 };
const SLACK = 60;

/// An item's secret as the app seals it into a grant: its kind, name and fields.
export type Secret = { kind: string; name: string; fields: Record<string, string> };

export type Held = { request: Request; grant: Grant; secret: Secret; uses: number };

/// Whether `host` is one of `patterns`: the same name, or under a `*.` pattern's domain (not the domain itself).
export function hostAllowed(host: string, patterns: string[]): boolean {
  const h = host.toLowerCase().replace(/\.$/, "");
  return patterns.some((p) => (p.startsWith("*.") ? h.endsWith(p.slice(1)) && h.length > p.length - 1 : h === p));
}

/// The value a grant's secret is used as: a token's value, a login's password, an SSH key's private key.
export function valueOf(secret: Secret): string | null {
  const f = secret.fields ?? {};
  const v = secret.kind === "ssh_key" ? f.private_key : secret.kind === "login" ? f.password : f.value;
  return typeof v === "string" && v !== "" ? v : null;
}

export class Keeper {
  readonly #boxes = new Map<string, Uint8Array>();
  readonly #held = new Map<string, Held>();
  /// Unix seconds.
  readonly #now: () => number;

  constructor(now: () => number) {
    this.#now = now;
  }

  /// A box for request `id`'s secret: its public half, to be sealed to; the private half stays here.
  open(id: string): string {
    const { pub, priv } = newBoxPair();
    this.#boxes.set(id, priv);
    return pub;
  }

  /// Takes `grant` for `request` (of `item` in `vault`, as the lock has it now); why not, or null when taken.
  accept(lock: LockState, vault: Vault, item: Item, request: Request, grant: Grant): string | null {
    const g = grant as any;
    if (g === null || typeof g !== "object" || g.v !== 1) return "a grant is {v: 1, …}";
    if (request.status !== "pending") return `the request is ${request.status}`;
    if (g.ws !== request.ws || g.request !== request.id || g.vault !== request.vault || g.item !== request.item || g.mode !== request.mode) return "the grant is not for this request as asked";
    if (vault.id !== request.vault || item.id !== request.item || item.deleted || item.listing === undefined) return "the item is not one agents may ask for";
    if (!item.listing.modes.includes(g.mode as Mode)) return `the item is not given by ${g.mode}`;
    if (!(g.scope in LASTS)) return "scope is once, hour or chat";
    const now = this.#now();
    if (!Number.isSafeInteger(g.exp) || g.exp <= now || g.exp > now + LASTS[g.scope as Scope] + SLACK) return "the grant's expiry is out of range for its scope";
    if (!Array.isArray(g.hosts) || !g.hosts.every((h: unknown) => typeof h === "string" && (item.listing!.hosts.includes(h) || (!h.startsWith("*.") && hostAllowed(h, item.listing!.hosts))))) {
      return "the grant's hosts are not all the item's";
    }
    if (g.mode === "proxy" && g.hosts.length === 0) return "a grant through the proxy names its hosts";
    const by = typeof g.sig?.key === "string" ? signerOf(lock, g.sig.key) : null;
    if (by === null || !vault.members.includes(by.sub)) return "a grant is signed by a vault member's device in the lock";
    if (!signedOk(g, TAG.grant)) return "the grant's signature is invalid";
    const box = this.#boxes.get(request.id);
    if (box === undefined) return "this station no longer holds the request's box (it restarted): ask again";
    let secret: Secret;
    try {
      secret = JSON.parse(Buffer.from(openSeal(box, g.secret, grantContext(request.ws, request.id))).toString("utf8"));
    } catch {
      return "the grant's secret does not open";
    }
    if (secret === null || typeof secret !== "object" || valueOf(secret) === null) return "the grant's secret has no value to use";
    this.#boxes.delete(request.id);
    this.#held.set(request.id, { request: { ...request, status: "granted" }, grant, secret, uses: 0 });
    return null;
  }

  /// The grant `id` as `session` may use it now; else why not.
  usable(session: string, id: string): Held | string {
    const h = this.#held.get(id);
    if (h === undefined) return "no such grant here: secret_list shows the grants you hold (a restart of the station forgets them; ask again)";
    if (h.request.session !== session) return "this grant is another session's";
    if (h.grant.exp <= this.#now()) {
      this.#held.delete(id);
      return "this grant ran out: ask again";
    }
    if (h.grant.scope === "once" && h.uses > 0) return "this grant was for one use and is used: ask again";
    return h;
  }

  /// One use of grant `id` begins (a command run with it).
  spend(id: string) {
    const h = this.#held.get(id);
    if (h !== undefined) h.uses++;
  }

  /// A request decided otherwise (denied, expired): its box is dropped.
  drop(id: string) {
    this.#boxes.delete(id);
    this.#held.delete(id);
  }

  /// The grants `session` holds that may still be used.
  held(session: string): Held[] {
    return [...this.#held.values()].filter((h) => typeof this.usable(session, h.request.id) !== "string");
  }

  /// Whether request `id` still has its box here.
  waiting(id: string): boolean {
    return this.#boxes.has(id);
  }
}
