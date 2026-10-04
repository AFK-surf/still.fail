// A member's credential, checked offline as the Rust station's main.rs `verify_member` does: an EdDSA JWT still.fail
// cloud signed with one of the workspace's grant keys, for this workspace and the device at the other end, unexpired
// and not revoked.
import { createPublicKey, verify } from "node:crypto";
import { wall } from "../ops/fibers.ts";

const MEMBER_TYPES = ["stillfail-member+jwt", "ember-member+jwt"];
const ISSUERS = ["stillfail-cloud", "ember-cloud"];

export type Viewer = { sub: string; email: string; name: string; role: string; workspace: string; device: string };
export type Admitted = { viewer: Viewer; exp: number; iat: number; sid: string };
export type Revocation = { kind: string; id: string; at: number };

const b64 = (s: string) => Buffer.from(s, "base64url");
/// Credentials' times are the cloud's, in the machine's time.
const now = () => Math.floor(wall.now() / 1000);

export function verifyMember(credential: string, keys: any, workspace: string, device: string, revocations: Revocation[]): Admitted {
  const parts = credential.split(".");
  if (parts.length !== 3) throw new Error("malformed credential");
  const [head, body, sig] = parts;
  const header = JSON.parse(b64(head).toString());
  if (header.alg !== "EdDSA" || !MEMBER_TYPES.includes(header.typ ?? "")) throw new Error("not a member's credential");
  const kid: string | undefined = typeof header.kid === "string" ? header.kid : undefined;
  const jwk = (Array.isArray(keys?.keys) ? keys.keys : []).find((k: any) => kid === undefined || k.kid === kid);
  if (!jwk) throw new Error("unknown credential key");
  const key = createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: jwk.x }, format: "jwk" });
  if (!verify(null, Buffer.from(`${head}.${body}`), key, b64(sig))) throw new Error("credential signature invalid");
  const claims = JSON.parse(b64(body).toString());
  const text = (k: string) => (typeof claims[k] === "string" ? claims[k] : "");
  if (!ISSUERS.includes(text("iss"))) throw new Error("credential not issued by still.fail cloud");
  if (text("ws") !== workspace) throw new Error("credential is for another workspace");
  if (text("device") !== device) throw new Error("credential is for another device");
  const exp = Number.isInteger(claims.exp) && claims.exp >= 0 ? claims.exp : 0;
  if (exp <= now()) throw new Error("credential expired");
  const admitted: Admitted = {
    viewer: { sub: text("sub"), email: text("email"), name: text("name"), role: text("role"), workspace: text("ws"), device },
    exp,
    iat: Number.isInteger(claims.iat) ? claims.iat : 0,
    sid: text("sid"),
  };
  if (revoked(admitted, revocations)) throw new Error("credential revoked");
  return admitted;
}

/// Taken back: its account's (`sub`) or session's (`sid`) credentials issued up to `at`.
export function revoked(admitted: Admitted, revocations: Revocation[]): boolean {
  return revocations.some((r) => admitted.iat <= r.at && ((r.kind === "sub" && r.id === admitted.viewer.sub) || (r.kind === "sid" && r.id === admitted.sid)));
}
