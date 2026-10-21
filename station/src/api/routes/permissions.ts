// What macOS lets still.fail Helper do on this Mac (helper/grants.ts; docs/remote-screens.md "Grants"), as members ask
// it. The overview says the grants (`permissions`); POST /permissions/request `{grant}` puts the helper's window up on
// the Mac for that one (a member who may change the station: the admin API refuses a read-only one's), again however
// lately it was shown (the person asks: a client retrying is answered once, by its idempotency key), and answers `{window, screen}`: `up` (shown, or up already asking for it) or `granted` (nothing
// to ask), and whether the screen can be seen and driven (the client then opens it, for the person to click in the
// window from wherever they are). Not shown: an error in the asker's words, 409 when a disk's grant has no disk of its
// kind to ask with, 503 when it could not be shown. A station without the helper has
// no such route (404).
import { type Answer, type Request, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import { readOnly } from "../../mesh/credential.ts";
import { askWords } from "../../helper/files.ts";
import { GrantRefused, type GrantsView, type HelperGrants, isGrant } from "../../helper/grants.ts";

const refused = (status: number, key: string, lang: Lang, args: Record<string, unknown> = {}): Answer =>
  json(status, JSON.stringify({ error: tr(lang, key, args) }));

/// What the overview says of them to `viewer`: the grants, and whether they may ask for one (null before the first
/// look, which is then made: told once known).
export function permissionsView(grants: HelperGrants, viewer: Request["viewer"]): (GrantsView & { request: boolean }) | null {
  const view = grants.view();
  return view === null ? null : { ...view, request: !readOnly(viewer) };
}

export function routes({ grants }: { grants: HelperGrants }): Route[] {
  return [
    {
      method: "POST",
      pattern: /^\/permissions\/request$/,
      handle: async (r: Request) => {
        let grant: unknown;
        try {
          grant = JSON.parse(r.body.toString("utf8") || "{}")?.grant;
        } catch {}
        if (!isGrant(grant)) return refused(400, "station.permissions.unknown", r.lang);
        try {
          const { window, screen } = await grants.request(grant, askWords(r.lang), true);
          if (window === "none") return refused(503, "station.permissions.none", r.lang);
          return json(200, JSON.stringify({ window, screen }));
        } catch (e) {
          if (e instanceof GrantRefused) return refused(e.key === "station.permissions.noHelper" ? 503 : e.key === "station.permissions.unknown" ? 400 : 409, e.key, r.lang);
          throw e;
        }
      },
    },
  ];
}
