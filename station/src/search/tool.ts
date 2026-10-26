// The agents' search (docs/search.md): what a few words find in the workspace, on every station of it at once: chats,
// messages, execution history, services and tasks, skills and memory, profiles, looked through as they are then. Each
// station answers for its own (`search.query`, asked over the mesh as session.read is), with the links of its chats.
import type { Asker, Group, Hit } from "./match.ts";
import type { Search } from "./search.ts";
import type { Tool } from "../tools/mcp.ts";
import { skillTools } from "./skills.ts";
import { wall } from "../ops/fibers.ts";

/// What another station is asked.
export const SEARCH = "search.query";
/// How long another station has to answer before it is said not to have.
const WAIT_MS = 20_000;
/// What is said of each kind at most, and of each hit.
const SHOWN = 5;
const TEXT_CHARS = 200;

const KINDS = ["chat", "message", "history", "job", "skill", "memory", "profile", "file"];

export type SearchDeps = {
  search: Search;
  readSkill(workspace: string | undefined, name: string, file: string): string;
  /// The workspace a session's chat is in (null: the station's home one) and whether that is the station's home one.
  workspaceOf(session: string): { workspace: string; home: boolean } | null;
  /// A chat's link (`…/o/<workspace>/<station>/<key>`), the one to give people.
  link(session: string): string | undefined;
  /// The other stations of the workspace, by id and name.
  stations(workspace: string): Promise<{ id: string; name: string; here: boolean }[]>;
  ask(station: string, request: Record<string, unknown>): Promise<any>;
};

/// Each hit with the link of its chat, where it is in one.
function linked(groups: Group[], link: (session: string) => string | undefined): Group[] {
  return groups.map((g) => ({ ...g, hits: g.hits.map((h) => (typeof h.chat === "string" && link(h.chat) ? { ...h, link: link(h.chat) } : h)) }));
}

/// What `request` asks of this station from another (`ws`: the workspace it was asked in; none: the home one).
export async function searchForPeer(deps: Pick<SearchDeps, "search" | "link">, request: any, ws: string | null, home: string | null): Promise<unknown> {
  const query = typeof request?.query === "string" ? request.query : "";
  const asked = Array.isArray(request?.kinds) ? request.kinds.filter((k: unknown): k is string => typeof k === "string") : [];
  // All of them, the execution history too, when none is named.
  const kinds = asked.length > 0 ? asked : KINDS;
  const limit = typeof request?.limit === "number" ? request.limit : SHOWN;
  const asker: Asker = { workspace: ws ?? home ?? "", home: ws === null || ws === home, scopes: ["write"] };
  const found = await deps.search.query(query, asker, { kinds, limit });
  return { groups: linked(found.groups, deps.link), building: found.building };
}

const one = (text: string) => {
  const flat = text.replace(/\s+/gu, " ").trim();
  return flat.length > TEXT_CHARS ? `${flat.slice(0, TEXT_CHARS)}…` : flat;
};

function hitLine(h: Hit): string {
  const where: string[] = [];
  if (typeof h.chatTitle === "string" && h.chatTitle !== "") where.push(`in “${h.chatTitle}”`);
  if (typeof h.link === "string") where.push(String(h.link));
  if (typeof h.seq === "number") where.push(`message #${h.seq}`);
  if (typeof h.index === "number") where.push(`history #${h.index}`);
  if (typeof h.job === "string") where.push(`job ${h.job}${typeof h.port === "number" ? ` (port ${h.port})` : ""}`);
  if (typeof h.path === "string") where.push(String(h.path));
  if (h.archived === true) where.push("archived");
  const at = typeof h.at === "number" ? ` (${new Date(h.at).toISOString().slice(0, 16).replace("T", " ")} UTC)` : "";
  const title = h.title !== "" ? `${h.title}: ` : "";
  return `- ${title}${one(h.text)}${at}${where.length > 0 ? ` — ${where.join(", ")}` : ""}`;
}

function said(name: string, groups: Group[], station: string): string {
  if (groups.length === 0) return `## ${name}\nNothing found.`;
  const parts = groups.map((g) => {
    const left = g.left ? `\n- … ${g.left} older sessions' history not looked through (out of time): narrow the words, or ask this station alone` : "";
    const more = g.more && !g.left ? "\n- … more: ask with kinds=[\"" + g.kind + "\"] and a higher limit" : "";
    return `### ${g.kind}\n${g.hits.map((h) => hitLine(h) + (g.kind === "skill" && typeof h.skill === "string" ? ` — read with skill_read ${JSON.stringify({ station, name: h.skill })}` : "")).join("\n")}${more}${left}`;
  });
  return `## ${name}\n${parts.join("\n")}`;
}

export function searchTools(deps: SearchDeps): Tool[] {
  return [
    ...skillTools(deps),
    {
      name: "search",
      description:
        "Search everything in this workspace, on all its stations at once: chats (titles, archived ones too), every message, agents' execution histories (what they said, thought and ran, and what it gave), services and tasks, skills and memory, profiles, and the files on each station's machine (names and what they say). Looked through as they are now (nothing indexed): the execution histories take a few seconds, the most recently active sessions first. Words are matched anywhere in the text, case aside; every word must match. Results are grouped by station and kind, newest first after title matches, with chat links to give people or read with chat_read and session_history. For project workflows missing from your local skill catalog, search kinds=[\"skill\"] across stations first; read a matching skill in full with skill_read.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "The words to find (at most 200 characters)." },
          kinds: { type: "array", items: { enum: KINDS }, description: "Only these kinds. Left out: all." },
          limit: { type: "integer", description: `At most this many of each kind on each station (default ${SHOWN}, at most 50).` },
          station: { type: "string", description: "Only this station, by its name or id. Left out: every station of the workspace." },
        },
        required: ["query"],
        additionalProperties: false,
      },
      run: async (session, args) => {
        const query = typeof args.query === "string" ? args.query.trim() : "";
        if (query === "") throw new Error("query is required");
        if (query.length > 200) throw new Error("a search is at most 200 characters");
        const asked = Array.isArray(args.kinds) ? args.kinds.filter((k): k is string => typeof k === "string") : [];
        const kinds = asked.length > 0 ? asked : KINDS;
        const limit = Math.max(1, Math.min(typeof args.limit === "number" ? Math.floor(args.limit) : SHOWN, 50));
        const place = deps.workspaceOf(session);
        if (place === null) throw new Error("unknown session");
        const only = typeof args.station === "string" ? args.station.trim().toLowerCase() : "";
        let stations: { id: string; name: string; here: boolean }[] = [];
        try {
          stations = await deps.stations(place.workspace);
        } catch {
          // In no workspace's mesh yet: this station alone.
        }
        if (!stations.some((s) => s.here)) stations.unshift({ id: "", name: "this station", here: true });
        const chosen = only === "" ? stations : stations.filter((s) => s.id.toLowerCase() === only || s.name.toLowerCase() === only);
        if (chosen.length === 0) throw new Error(`no station ${JSON.stringify(args.station)} in this workspace`);
        const parts = await Promise.all(
          chosen.map(async (s) => {
            const name = s.here ? `${s.name} (this station)` : s.name;
            try {
              if (s.here) {
                const found = await deps.search.query(query, { ...place, scopes: ["write"] }, { kinds, limit });
                return said(name, linked(found.groups, deps.link), s.id || s.name);
              }
              const answer = await wall.within(WAIT_MS, deps.ask(s.id, { method: SEARCH, session, workspace: place.workspace, query, kinds, limit }), `did not answer within ${WAIT_MS / 1000} s`);
              return said(name, Array.isArray(answer?.groups) ? answer.groups : [], s.id);
            } catch (error) {
              return `## ${name}\nNot searched: ${(error as Error).message}`;
            }
          }),
        );
        return `Search for ${JSON.stringify(query)}:\n\n${parts.join("\n\n")}`;
      },
    },
  ];
}
