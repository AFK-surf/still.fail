// A workspace's presets (sessions/presets.ts): GET /presets lists them with the directories offered
// for a new one; POST makes one, PUT /presets/:id changes it, DELETE removes it. Each member sees and changes their own
// workspace's. POST /presets/clone clones a repository from git into the station's repository cache for them to pick
// (sessions/clones.ts), answered at once; GET /presets lists those under way and failed (`clones`), DELETE
// /presets/clones/:id stops or forgets one. Any of those changed, or the machine's repositories found after they were
// asked for, is told (`presets`): the devices read them again. A chat is opened with one by POST /sessions `preset`
// (routes/hub.ts).
//
// Those are what an app from before asks, and answer it as before: GET /presets lists only the presets made here
// (`home`), so that one carried to every station is not shown once a station; POST, PUT and DELETE change one here
// (sessions/presets.ts: the only changes a station makes itself). A core of now carries its person's (the station's
// AGENTS.md, Presets and stars): GET /presets/kept gives the asker's own records, deleted ones too; GET
// /presets/others everyone else's live ones (asked at a press); PUT /presets/kept `{records}` takes those of the
// asker's that are newer, as they were brought, answering `{records, refused}`: what is kept now of each id asked, and
// what was not taken with why. A station from before answers GET /presets/kept 404 `no route …`, which is how a core
// knows it (its PUT /presets/kept would be taken for PUT /presets/:id and answered 404 `no preset kept`: ask GET first).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { tr } from "../../ops/i18n.ts";
import { readOnly } from "../../mesh/credential.ts";
import { type Asker, NoPreset, type Presets, type RepoIndex, candidates } from "../../sessions/presets.ts";
import { type Clones, NoCloneUrl } from "../../sessions/clones.ts";

export type PresetDeps = { presets: Presets; reposDir: () => string; index?: RepoIndex; clones?: Clones; changed?: () => void };

function body(r: Request): unknown {
  try {
    return JSON.parse(r.body.toString("utf8") || "{}");
  } catch {
    throw new Error("invalid JSON");
  }
}

const wsOf = (r: Request) => r.viewer.workspace || null;
const askerOf = (r: Request): Asker => ({ sub: r.viewer.sub ?? "", email: r.viewer.email ?? "" });

/// A PUT /presets/kept body is a megabyte at most (api/request.ts `input`), of so many records at most: a device with
/// more brings them in turns.
export const CARRIED_MOST = 100;
const BODY_MOST = 1_000_000;

const failed = (e: unknown): Answer => (e instanceof NoPreset ? error(404, e.message) : error(400, (e as Error).message));

export const routes = ({ presets, reposDir, index, clones, changed }: PresetDeps): Route[] => [
  {
    method: "GET",
    pattern: /^\/presets$/,
    handle: async (r: Request): Promise<Answer> => {
      const list = presets.listed(wsOf(r));
      const offered = await candidates(reposDir(), presets.list(wsOf(r)), (await index?.repos(changed)) ?? [], (s) => presets.isHere(s));
      return json(200, JSON.stringify({ presets: list, candidates: offered, clones: clones?.list(wsOf(r)) ?? [] }));
    },
  },
  {
    method: "GET",
    pattern: /^\/presets\/kept$/,
    handle: async (r: Request): Promise<Answer> => json(200, JSON.stringify({ records: presets.kept(wsOf(r), askerOf(r)) })),
  },
  {
    method: "GET",
    pattern: /^\/presets\/others$/,
    handle: async (r: Request): Promise<Answer> => json(200, JSON.stringify({ records: presets.others(wsOf(r), askerOf(r)) })),
  },
  {
    method: "PUT",
    pattern: /^\/presets\/kept$/,
    handle: async (r: Request): Promise<Answer> => {
      if (r.body.length > BODY_MOST) return error(413, `request too large: at most ${CARRIED_MOST} records and a megabyte at a time`);
      let given: unknown;
      try {
        given = (body(r) as { records?: unknown } | null)?.records;
      } catch (e) {
        return failed(e);
      }
      if (!Array.isArray(given)) return error(400, "records: a list of presets' records");
      if (given.length > CARRIED_MOST) return error(413, `at most ${CARRIED_MOST} records at a time`);
      const who = askerOf(r);
      if (who.sub === "") return error(403, "records are taken only from a person's own devices");
      const carried = presets.carry(wsOf(r), who, given);
      if (carried.changed) {
        log.info("presets", "records carried here", { by: r.viewer.email, given: given.length, refused: carried.refused.length });
        changed?.();
      }
      return json(200, JSON.stringify({ records: carried.records, refused: carried.refused }));
    },
  },
  ...(clones
    ? [
        {
          method: "POST",
          pattern: /^\/presets\/clone$/,
          handle: async (r: Request): Promise<Answer> => {
            if (readOnly(r.viewer)) return json(403, JSON.stringify({ error: tr(r.lang, "station.presets.clone.readOnly") }));
            try {
              const given = (body(r) as { url?: unknown } | null)?.url;
              return json(200, JSON.stringify(await clones.start(wsOf(r), given, r.viewer.email, () => changed?.())));
            } catch (e) {
              return e instanceof NoCloneUrl ? json(400, JSON.stringify({ error: tr(r.lang, "station.presets.clone.invalid") })) : failed(e);
            }
          },
        } as Route,
        {
          method: "DELETE",
          pattern: /^\/presets\/clones\/([A-Za-z0-9_-]+)$/,
          handle: async (r: Request, [id]: string[]): Promise<Answer> => {
            if (readOnly(r.viewer)) return json(403, JSON.stringify({ error: tr(r.lang, "station.presets.clone.readOnly") }));
            if (!clones.drop(wsOf(r), id!)) return error(404, `no clone ${id}`);
            return json(200, JSON.stringify({ ok: true }));
          },
        } as Route,
      ]
    : []),
  {
    method: "POST",
    pattern: /^\/presets$/,
    handle: async (r: Request): Promise<Answer> => {
      try {
        const p = presets.add(wsOf(r), body(r), r.viewer.email, r.viewer.sub ?? "");
        log.info("presets", "preset made", { id: p.id, dirs: p.dirs.length, by: r.viewer.email });
        changed?.();
        return json(200, JSON.stringify(p));
      } catch (e) {
        return failed(e);
      }
    },
  },
  {
    method: "PUT",
    pattern: /^\/presets\/([A-Za-z0-9_-]+)$/,
    handle: async (r: Request, [id]: string[]): Promise<Answer> => {
      try {
        const p = presets.put(wsOf(r), id!, body(r), askerOf(r));
        log.info("presets", "preset changed", { id: p.id, by: r.viewer.email });
        changed?.();
        return json(200, JSON.stringify(p));
      } catch (e) {
        return failed(e);
      }
    },
  },
  {
    method: "DELETE",
    pattern: /^\/presets\/([A-Za-z0-9_-]+)$/,
    handle: async (r: Request, [id]: string[]): Promise<Answer> => {
      try {
        presets.delete(wsOf(r), id!, askerOf(r));
        log.info("presets", "preset removed", { id, by: r.viewer.email });
        changed?.();
        return json(200, JSON.stringify({ ok: true }));
      } catch (e) {
        return failed(e);
      }
    },
  },
];
