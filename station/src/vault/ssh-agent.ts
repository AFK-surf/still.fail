// The keeper's ssh-agent (docs/vault.md, 三种用法): a socket for one command run with a granted SSH key, which lists
// that key and signs with it, so the key itself never leaves the keeper. The agent protocol's few messages it needs
// (draft-miller-ssh-agent): list identities, sign; anything else fails. Keys are OpenSSH's own format
// (`openssh-key-v1`, unencrypted) or PEM, Ed25519 or RSA.
import { type KeyObject, createPrivateKey, createPublicKey, sign } from "node:crypto";
import { type Server, type Socket, createServer } from "node:net";

const REQUEST_IDENTITIES = 11;
const IDENTITIES_ANSWER = 12;
const SIGN_REQUEST = 13;
const SIGN_RESPONSE = 14;
const FAILURE = 5;
const RSA_SHA2_256 = 2;
const RSA_SHA2_512 = 4;

/// A key as the agent holds it: the private key, and its public blob as SSH writes it.
export type SshKey = { key: KeyObject; blob: Buffer; kind: "ssh-ed25519" | "ssh-rsa"; comment: string };

const u32 = (n: number) => {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n);
  return b;
};
const string = (b: Buffer | string) => {
  const v = typeof b === "string" ? Buffer.from(b) : b;
  return Buffer.concat([u32(v.length), v]);
};
/// An mpint from big-endian unsigned bytes.
const mpint = (b: Buffer) => {
  let i = 0;
  while (i < b.length && b[i] === 0) i++;
  const v = b.subarray(i);
  return string(v.length > 0 && v[0]! & 0x80 ? Buffer.concat([Buffer.from([0]), v]) : v);
};

/// Reads SSH's wire types off a buffer, throwing past its end.
class Reader {
  at = 0;
  constructor(readonly b: Buffer) {}
  u32(): number {
    if (this.at + 4 > this.b.length) throw new Error("truncated");
    const v = this.b.readUInt32BE(this.at);
    this.at += 4;
    return v;
  }
  bytes(): Buffer {
    const n = this.u32();
    if (this.at + n > this.b.length) throw new Error("truncated");
    const v = this.b.subarray(this.at, this.at + n);
    this.at += n;
    return v;
  }
  text = () => this.bytes().toString("utf8");
}

const b64u = (b: Buffer) => {
  let i = 0;
  while (i < b.length - 1 && b[i] === 0) i++;
  return b.subarray(i).toString("base64url");
};
const big = (b: Buffer) => BigInt(`0x${b.toString("hex") || "0"}`);
const unbig = (n: bigint) => {
  const hex = n.toString(16);
  return Buffer.from(hex.length % 2 ? `0${hex}` : hex, "hex");
};

/// An Ed25519 key from its 32-byte seed: PKCS#8 is a fixed prefix and the seed.
const ED25519_PKCS8 = Buffer.from("302e020100300506032b657004220420", "hex");
function ed25519(seed: Buffer, comment: string): SshKey {
  const key = createPrivateKey({ key: Buffer.concat([ED25519_PKCS8, seed]), format: "der", type: "pkcs8" });
  return fromKey(createPublicKey(key), key, comment);
}

/// The agent's view of a private key node:crypto holds.
function fromKey(pub: KeyObject, key: KeyObject, comment: string): SshKey {
  const jwk = pub.export({ format: "jwk" });
  if (jwk.kty === "OKP" && jwk.crv === "Ed25519") {
    return { key, kind: "ssh-ed25519", comment, blob: Buffer.concat([string("ssh-ed25519"), string(Buffer.from(jwk.x!, "base64url"))]) };
  }
  if (jwk.kty === "RSA") {
    return { key, kind: "ssh-rsa", comment, blob: Buffer.concat([string("ssh-rsa"), mpint(Buffer.from(jwk.e!, "base64url")), mpint(Buffer.from(jwk.n!, "base64url"))]) };
  }
  throw new Error("only Ed25519 and RSA SSH keys are supported");
}

/// A private key from its text: OpenSSH's format (unencrypted) or PEM.
export function parseSshKey(text: string): SshKey {
  const body = /-----BEGIN OPENSSH PRIVATE KEY-----([\s\S]*?)-----END OPENSSH PRIVATE KEY-----/.exec(text);
  if (body === null) {
    const key = createPrivateKey(text);
    return fromKey(createPublicKey(key), key, "");
  }
  const raw = Buffer.from(body[1]!.replace(/\s+/g, ""), "base64");
  const magic = "openssh-key-v1\0";
  if (raw.subarray(0, magic.length).toString("latin1") !== magic) throw new Error("not an OpenSSH private key");
  const r = new Reader(raw.subarray(magic.length));
  const cipher = r.text();
  r.text();
  r.bytes();
  if (cipher !== "none") throw new Error("the SSH key has a passphrase: store it without one (the vault keeps it encrypted)");
  if (r.u32() !== 1) throw new Error("one key per SSH key file");
  r.bytes();
  const p = new Reader(r.bytes());
  if (p.u32() !== p.u32()) throw new Error("the SSH key is damaged");
  const kind = p.text();
  if (kind === "ssh-ed25519") {
    p.bytes();
    const secret = p.bytes();
    return ed25519(Buffer.from(secret.subarray(0, 32)), p.text());
  }
  if (kind === "ssh-rsa") {
    const [n, e, d, iqmp, pp, q] = [p.bytes(), p.bytes(), p.bytes(), p.bytes(), p.bytes(), p.bytes()];
    const comment = p.text();
    const D = big(d);
    const key = createPrivateKey({
      key: {
        kty: "RSA", n: b64u(n), e: b64u(e), d: b64u(d), p: b64u(pp), q: b64u(q),
        dp: unbig(D % (big(pp) - 1n)).toString("base64url"), dq: unbig(D % (big(q) - 1n)).toString("base64url"), qi: b64u(iqmp),
      },
      format: "jwk",
    });
    return fromKey(createPublicKey(key), key, comment);
  }
  throw new Error(`only Ed25519 and RSA SSH keys are supported, not ${kind}`);
}

/// The signature blob for `data` with `k`, as `flags` ask (RSA: SHA-2 when asked, else SHA-1 as ssh-rsa).
export function sshSign(k: SshKey, data: Buffer, flags: number): Buffer {
  if (k.kind === "ssh-ed25519") return Buffer.concat([string("ssh-ed25519"), string(sign(null, data, k.key))]);
  const [name, hash] = flags & RSA_SHA2_512 ? ["rsa-sha2-512", "sha512"] : flags & RSA_SHA2_256 ? ["rsa-sha2-256", "sha256"] : ["ssh-rsa", "sha1"];
  return Buffer.concat([string(name), string(sign(hash, data, k.key))]);
}

/// The answer to one agent message (its type byte and payload); `allowed` is asked before each signature.
export function answer(k: SshKey, message: Buffer, allowed: () => boolean): Buffer {
  const type = message[0];
  try {
    if (type === REQUEST_IDENTITIES) return Buffer.concat([Buffer.from([IDENTITIES_ANSWER]), u32(1), string(k.blob), string(k.comment)]);
    if (type === SIGN_REQUEST) {
      const r = new Reader(message.subarray(1));
      const blob = r.bytes();
      const data = r.bytes();
      const flags = r.u32();
      if (blob.equals(k.blob) && allowed()) return Buffer.concat([Buffer.from([SIGN_RESPONSE]), string(sshSign(k, data, flags))]);
    }
  } catch {
    // A malformed message: fails as any other.
  }
  return Buffer.from([FAILURE]);
}

/// Serves the agent on `path` (a Unix socket) until closed.
export function serveAgent(path: string, k: SshKey, allowed: () => boolean): Promise<Server> {
  const server = createServer((socket: Socket) => {
    let held = Buffer.alloc(0);
    socket.on("data", (chunk: Buffer) => {
      held = Buffer.concat([held, chunk]);
      while (held.length >= 4) {
        const n = held.readUInt32BE(0);
        if (n > 256 * 1024) return void socket.destroy();
        if (held.length < 4 + n) break;
        const reply = answer(k, held.subarray(4, 4 + n), allowed);
        held = held.subarray(4 + n);
        socket.write(Buffer.concat([u32(reply.length), reply]));
      }
    });
    socket.on("error", () => socket.destroy());
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(path, () => {
      server.off("error", reject);
      resolve(server);
    });
  });
}
