// A member's credential, checked offline as the Rust station's main.rs `verify_member` does: an EdDSA JWT the control
// plane signed with one of the workspace's grant keys, for this workspace and the device at the other end, unexpired
// and not revoked. Which issuer and type it bears is the provider's (cloud/provider.ts): still.fail cloud's unless
// told otherwise.
import { createPublicKey, verify } from "node:crypto";
import { type Accepted, STILLFAIL } from "../cloud/provider.ts";
import { wall } from "../ops/fibers.ts";

/// `lockDevice`: the device's base key and its proof for this endpoint, as its hello gave them (cloud/lock.ts).
/// `home`: whether `workspace` is the station's home one (docs/multi-workspace.md), as of the request; absent is yes.
export type Viewer = { sub: string; email: string; name: string; role: string; workspace: string; device: string; lockDevice?: { base: string; proof: string }; home?: boolean };
export type Admitted = { viewer: Viewer; exp: number; iat: number; sid: string };
export type Revocation = { kind: string; id: string; at: number };

const b64 = (s: string) => Buffer.from(s, "base64url");
/// Credentials' times are the cloud's, in the machine's time.
const now = () => Math.floor(wall.now() / 1000);

export function verifyMember(credential: string, keys: any, workspace: string, device: string, revocations: Revocation[], accepted: Accepted = STILLFAIL.credential): Admitted {
  const parts = credential.split(".");
  if (parts.length !== 3) throw new Error("malformed credential");
  const [head, body, sig] = parts;
  const header = JSON.parse(b64(head).toString());
  if (header.alg !== "EdDSA" || !accepted.types.includes(header.typ ?? "")) throw new Error("not a member's credential");
  const kid: string | undefined = typeof header.kid === "string" ? header.kid : undefined;
  const jwk = (Array.isArray(keys?.keys) ? keys.keys : []).find((k: any) => kid === undefined || k.kid === kid);
  if (!jwk) throw new Error("unknown credential key");
  const key = createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: jwk.x }, format: "jwk" });
  if (!verify(null, Buffer.from(`${head}.${body}`), key, b64(sig))) throw new Error("credential signature invalid");
  const claims = JSON.parse(b64(body).toString());
  const text = (k: string) => (typeof claims[k] === "string" ? claims[k] : "");
  if (!accepted.issuers.includes(text("iss"))) throw new Error(accepted === STILLFAIL.credential ? "credential not issued by still.fail cloud" : "credential not issued by the control plane");
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

/// A credential for any of the workspaces the station is in (docs/multi-workspace.md), checked as `verifyMember` does
/// against that workspace's revocations.
export function verifyMemberOf(credential: string, keys: any, memberships: { workspace: string; revocations: Revocation[] }[], device: string, accepted: Accepted = STILLFAIL.credential): Admitted {
  let ws = "";
  try {
    ws = JSON.parse(b64(credential.split(".")[1] ?? "").toString())?.ws ?? "";
  } catch {
    // Malformed: verifyMember says how.
  }
  const of = memberships.find((m) => m.workspace === ws) ?? memberships[0];
  return verifyMember(credential, keys, of?.workspace ?? "", device, of?.revocations ?? [], accepted);
}

/// Roles that may read but not write: no messages sent, nothing changed (contract §4).
export const READ_ONLY_ROLES = ["viewer"];

export const readOnly = (viewer: { role: string }) => READ_ONLY_ROLES.includes(viewer.role);

/// Who manages the station itself (its accounts, updates, device tools, what it shares, the workspaces it joins): an
/// owner or admin of its home workspace (docs/multi-workspace.md).
export const managesStation = (viewer: { role: string; home?: boolean }) => (viewer.role === "owner" || viewer.role === "admin") && viewer.home !== false;

/// Taken back: its account's (`sub`) or session's (`sid`) credentials issued up to `at`.
export function revoked(admitted: Admitted, revocations: Revocation[]): boolean {
  return revocations.some((r) => admitted.iat <= r.at && ((r.kind === "sub" && r.id === admitted.viewer.sub) || (r.kind === "sid" && r.id === admitted.sid)));
}
