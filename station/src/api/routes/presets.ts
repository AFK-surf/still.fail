// A workspace's presets (sessions/presets.ts, docs/presets.md): GET /presets lists them with the directories offered
// for a new one; POST makes one, PUT /presets/:id changes it, DELETE removes it. Each member sees and changes their own
// workspace's. Any of those changed, or the machine's repositories found after they were asked for, is told
// (`presets`): the devices read them again. A chat is opened with one by POST /sessions `preset` (routes/hub.ts).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { NoPreset, type Presets, type RepoIndex, candidates } from "../../sessions/presets.ts";

export type PresetDeps = { presets: Presets; reposDir: () => string; index?: RepoIndex; changed?: () => void };

function body(r: Request): unknown {
  try {
    return JSON.parse(r.body.toString("utf8") || "{}");
  } catch {
    throw new Error("invalid JSON");
  }
}

const wsOf = (r: Request) => r.viewer.workspace || null;

const failed = (e: unknown): Answer => (e instanceof NoPreset ? error(404, e.message) : error(400, (e as Error).message));

export const routes = ({ presets, reposDir, index, changed }: PresetDeps): Route[] => [
  {
    method: "GET",
    pattern: /^\/presets$/,
    handle: async (r: Request): Promise<Answer> => {
      const list = presets.list(wsOf(r));
      return json(200, JSON.stringify({ presets: list, candidates: await candidates(reposDir(), list, (await index?.repos(changed)) ?? []) }));
    },
  },
  {
    method: "POST",
    pattern: /^\/presets$/,
    handle: async (r: Request): Promise<Answer> => {
      try {
        const p = presets.add(wsOf(r), body(r), r.viewer.email);
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
        const p = presets.put(wsOf(r), id!, body(r));
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
        presets.delete(wsOf(r), id!);
        log.info("presets", "preset removed", { id, by: r.viewer.email });
        changed?.();
        return json(200, JSON.stringify({ ok: true }));
      } catch (e) {
        return failed(e);
      }
    },
  },
];
