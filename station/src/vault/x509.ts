// The certificates the keeper's proxy shows (docs/vault.md, keeper): its own CA, made once and kept in the station's data
// directory, and a short-lived certificate for each host a grant is for, signed by it. node:crypto reads certificates
// but does not make them, so this writes the DER itself: ECDSA P-256 with SHA-256, and the extensions strict verifiers
// ask for (Python 3.13's VERIFY_X509_STRICT: key identifiers, a critical basic constraint and key usage on the CA).
import { type KeyObject, createHash, createPublicKey, generateKeyPairSync, randomBytes, sign } from "node:crypto";

const DAY = 86400_000;

function length(n: number): Buffer {
  if (n < 0x80) return Buffer.from([n]);
  const bytes: number[] = [];
  for (let v = n; v > 0; v = Math.floor(v / 256)) bytes.unshift(v & 0xff);
  return Buffer.from([0x80 | bytes.length, ...bytes]);
}

const tlv = (tag: number, ...content: Buffer[]) => {
  const body = Buffer.concat(content);
  return Buffer.concat([Buffer.from([tag]), length(body.length), body]);
};
const seq = (...parts: Buffer[]) => tlv(0x30, ...parts);
const set = (...parts: Buffer[]) => tlv(0x31, ...parts);
const explicit = (n: number, ...parts: Buffer[]) => tlv(0xa0 + n, ...parts);
const octets = (b: Buffer) => tlv(0x04, b);
const bits = (b: Buffer, unused = 0) => tlv(0x03, Buffer.from([unused]), b);
const yes = tlv(0x01, Buffer.from([0xff]));

/// A non-negative INTEGER from its big-endian bytes.
function integer(b: Buffer): Buffer {
  let i = 0;
  while (i < b.length - 1 && b[i] === 0) i++;
  const v = b.subarray(i);
  return tlv(0x02, v[0]! & 0x80 ? Buffer.concat([Buffer.from([0]), v]) : v);
}

function oid(dotted: string): Buffer {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  const out = [a! * 40 + b!];
  for (const n of rest) {
    const groups: number[] = [];
    for (let v = n; ; v = Math.floor(v / 128)) {
      groups.unshift(v % 128);
      if (v < 128) break;
    }
    out.push(...groups.map((g, i) => (i < groups.length - 1 ? g | 0x80 : g)));
  }
  return tlv(0x06, Buffer.from(out));
}

/// UTCTime until 2050, GeneralizedTime after, as RFC 5280 has it.
function time(ms: number): Buffer {
  const iso = new Date(ms).toISOString();
  const digits = iso.slice(0, 19).replace(/[-:T]/g, "");
  return Number(iso.slice(0, 4)) < 2050 ? tlv(0x17, Buffer.from(`${digits.slice(2)}Z`)) : tlv(0x18, Buffer.from(`${digits}Z`));
}

const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), tlv(0x0c, Buffer.from(cn, "utf8")))));
const extension = (id: string, critical: boolean, value: Buffer) => seq(oid(id), ...(critical ? [yes] : []), octets(value));
const ECDSA_SHA256 = seq(oid("1.2.840.10045.4.3.2"));

/// A key's point (`04‖x‖y`) and its identifier: the SHA-1 of it, as RFC 5280 suggests.
function keyId(key: KeyObject): Buffer {
  const jwk = key.export({ format: "jwk" });
  const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]);
  return createHash("sha1").update(point).digest();
}

type Made = { cert: Buffer; key: KeyObject };

/// A certificate for `key`'s public half named `cn`, signed with `issuer`'s key (its own when there is none: a CA's).
function certificate(cn: string, key: KeyObject, issuer: { cn: string; key: KeyObject } | null, extensions: Buffer[], from: number, to: number): Buffer {
  const spki = createPublicKey(key).export({ format: "der", type: "spki" });
  const tbs = seq(
    explicit(0, integer(Buffer.from([2]))),
    integer(Buffer.concat([Buffer.from([0x40 | (randomBytes(1)[0]! & 0x3f)]), randomBytes(15)])),
    ECDSA_SHA256,
    name(issuer?.cn ?? cn),
    seq(time(from), time(to)),
    name(cn),
    spki,
    explicit(3, seq(...extensions)),
  );
  const signature = sign("sha256", tbs, { key: issuer?.key ?? key, dsaEncoding: "der" });
  return seq(tbs, ECDSA_SHA256, bits(signature));
}

/// A new CA: its certificate and private key, good for ten years from `now`.
export function makeCa(now: number, cn = "still.fail station vault"): Made {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const id = keyId(createPublicKey(privateKey));
  const extensions = [
    extension("2.5.29.19", true, seq(yes)),
    // digitalSignature, keyCertSign, cRLSign.
    extension("2.5.29.15", true, bits(Buffer.from([0x86]), 1)),
    extension("2.5.29.14", false, octets(id)),
  ];
  return { cert: certificate(cn, privateKey, null, extensions, now - DAY, now + 3650 * DAY), key: privateKey };
}

/// A certificate for `host` signed by `ca`, good for a week from `now`, with a key of its own.
export function makeLeaf(ca: Made, caName: string, host: string, now: number): Made {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const extensions = [
    extension("2.5.29.19", true, seq()),
    // digitalSignature.
    extension("2.5.29.15", true, bits(Buffer.from([0x80]), 7)),
    extension("2.5.29.37", false, seq(oid("1.3.6.1.5.5.7.3.1"))),
    extension("2.5.29.17", false, seq(tlv(0x82, Buffer.from(host, "ascii")))),
    extension("2.5.29.14", false, octets(keyId(createPublicKey(privateKey)))),
    extension("2.5.29.35", false, seq(tlv(0x80, keyId(createPublicKey(ca.key))))),
  ];
  return { cert: certificate(host, privateKey, { cn: caName, key: ca.key }, extensions, now - DAY, now + 7 * DAY), key: privateKey };
}

/// DER as PEM.
export const pem = (der: Buffer, label = "CERTIFICATE") => `-----BEGIN ${label}-----\n${der.toString("base64").replace(/.{64}/g, "$&\n").replace(/\n?$/, "\n")}-----END ${label}-----\n`;
