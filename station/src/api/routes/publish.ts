// Chats published as snapshots (docs/public-share.md), from the pages: a chat as its snapshot would show it (a preview,
// nothing kept), the snapshot written out, and one taken down. Read-only members ask none of these (admin.ts
// `readOnlyMay`: they are writes). No agent's tool does: a person publishes.
import { type Request, type Answer, error, json, percentDecode } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { tr } from "../../ops/i18n.ts";
import { NotPublished, publish } from "../../publish/index.ts";
import type { Draft } from "../../publish/snapshot.ts";

/// A request's JSON object: nothing is `{}`, as is anything not an object; more than a megabyte refused.
function input(r: Request): Record<string, any> | null {
  if (r.body.length > 1_000_000 || r.body.length === 0) return r.body.length === 0 ? {} : null;
  try {
    const value = JSON.parse(r.body.toString("utf8"));
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
  } catch {
    return null;
  }
}

/// `{email: name}` as the client gives the workspace's people: strings only.
function namesOf(v: unknown): Record<string, string> {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return {};
  return Object.fromEntries(Object.entries(v).filter((e): e is [string, string] => typeof e[1] === "string"));
}

export const routes = ({ read, store, agents }: Tools): Route[] => {
  /// The chat as its snapshot would show it, up to `upto` (its latest message without it), or the readers' refusal.
  const draft = async (r: Request, thread: number, upto: number | null, names: Record<string, string>): Promise<Draft | Answer> => {
    const answer = await read(r, "publishDraft", { thread, upto, names, viewer: r.viewer.email, lang: r.lang });
    if (answer.status !== 200) return answer;
    return JSON.parse((answer.body as Buffer).toString("utf8")) as Draft;
  };
  const isAnswer = (v: Draft | Answer): v is Answer => "status" in v;
  const threadOf = (raw: string) => (/^\d+$/.test(raw) ? Number(raw) : null);
  return [
    {
      // What publishing it would show: the snapshot, what was hidden in which message, the attachments to tick (where each
      // is, and the session that keeps it: the members' pages show them as the chat does).
      method: "POST",
      pattern: /^\/*threads\/+([^/]+)\/+publish\/+preview\/*$/,
      handle: async (r, [raw]) => {
        const thread = threadOf(raw!);
        const i = input(r);
        if (thread === null) return error(404, tr(r.lang, "station.publish.noChat"));
        if (i === null) return error(400, "invalid JSON");
        const d = await draft(r, thread, null, namesOf(i.names));
        if (isAnswer(d)) return d;
        return json(200, JSON.stringify({
          upto: d.upto,
          title: d.title,
          entries: d.entries,
          redacted: d.redacted,
          files: d.files,
        }));
      },
    },
    {
      // Publishes it as the preview showed it: up to `upto`, with the attachments `files` (their `k`).
      method: "POST",
      pattern: /^\/*threads\/+([^/]+)\/+publish\/*$/,
      handle: async (r, [raw]) => {
        const thread = threadOf(raw!);
        const i = input(r);
        if (thread === null) return error(404, tr(r.lang, "station.publish.noChat"));
        if (i === null) return error(400, "invalid JSON");
        if (store === undefined || agents === undefined) return error(503, "station starting");
        if (typeof i.upto !== "number" || !Number.isSafeInteger(i.upto) || !Array.isArray(i.files)) return error(400, "upto: a message's n; files: [k]");
        const d = await draft(r, thread, i.upto, namesOf(i.names));
        if (isAnswer(d)) return d;
        try {
          const published = await publish(
            agents.hub,
            store,
            d,
            { thread, ticked: i.files.filter((k: unknown): k is string => typeof k === "string"), station: agents.place()?.name ?? "", by: { email: r.viewer.email, name: r.viewer.name || r.viewer.email.split("@")[0]! } },
            { fileGone: (name) => tr(r.lang, "station.publish.fileGone", { name }) },
          );
          return json(200, JSON.stringify({ published: { id: published.id, key: published.key, title: published.title, by: published.by, byName: published.byName, at: published.at, upto: published.upto, size: published.size } }));
        } catch (e) {
          if (e instanceof NotPublished) return error(e.status, e.message);
          throw e;
        }
      },
    },
    {
      // Takes it down: whoever published it, or a workspace owner or admin.
      method: "DELETE",
      pattern: /^\/*published\/+([^/]+)\/*$/,
      handle: async (r, [raw]) => {
        if (store === undefined) return error(503, "station starting");
        const id = percentDecode(raw!);
        const p = store.published(id);
        if (p === null) return error(404, tr(r.lang, "station.publish.notFound"));
        if (p.by !== r.viewer.email && r.viewer.role !== "owner" && r.viewer.role !== "admin") return error(403, tr(r.lang, "station.publish.notYours"));
        store.removePublished(id);
        return json(200, '{"ok":true}');
      },
    },
  ];
};
