// A sign-in asked of a person on its card (vault/signin.ts, docs/vault.md 登录态 "Signing in from a card"), answered from
// their app: POST browser/sign-ins/<id>/fill `{username?, password?, code?, keep?}` (what their password manager gave,
// or the code the page asks; typed into the chat's tab by the station, never kept), POST browser/sign-ins/<id>/self
// `{done?}` (they sign in themselves on the tab's screen, or say they did), POST browser/sign-ins/<id>/deny. Only the
// person the chat's agent works for, in its workspace; how it goes is said on the card.
import type { SignIns } from "../../vault/signin.ts";
import type { Route } from "../admin.ts";
import { type Answer, type Request, json } from "../request.ts";

function body(r: Request): any {
  try {
    const o = JSON.parse(r.body.toString("utf8") || "{}");
    return o !== null && typeof o === "object" ? o : {};
  } catch {
    return {};
  }
}

const answered = (why: string | null): Answer =>
  why === null ? json(200, JSON.stringify({ ok: true })) : json(409, JSON.stringify({ error: why, code: "signin_refused" }));

export const routes = (signIns: SignIns): Route[] => {
  const id = (r: Request) => decodeURIComponent(r.path.split("/")[3] ?? "");
  return [
    {
      method: "POST",
      pattern: /^\/browser\/sign-ins\/[^/]+\/fill$/,
      handle: async (r) => {
        const o = body(r);
        const str = (k: string) => (typeof o[k] === "string" ? (o[k] as string) : undefined);
        return answered(signIns.fill(r.viewer.email, r.viewer.workspace, id(r), {
          ...(str("username") !== undefined ? { username: str("username")! } : {}),
          ...(str("password") !== undefined ? { password: str("password")! } : {}),
          ...(str("code") !== undefined ? { code: str("code")! } : {}),
          ...(typeof o.keep === "boolean" ? { keep: o.keep } : {}),
        }));
      },
    },
    {
      method: "POST",
      pattern: /^\/browser\/sign-ins\/[^/]+\/self$/,
      handle: async (r) => answered(signIns.self(r.viewer.email, r.viewer.workspace, id(r), body(r).done === true)),
    },
    {
      method: "POST",
      pattern: /^\/browser\/sign-ins\/[^/]+\/deny$/,
      handle: async (r) => answered(signIns.deny(r.viewer.email, r.viewer.workspace, id(r))),
    },
  ];
};
