// Read a skill found by workspace search, using the same workspace-scoped catalog as search and GET /memory.
import { memory } from "../read/memory.ts";
import type { Tool } from "../tools/mcp.ts";
import { wall } from "../ops/fibers.ts";
import type { SearchDeps } from "./tool.ts";

export const SKILL_READ = "skill.read";

function selection(args: Record<string, unknown>): { name: string; file: string } {
  if (typeof args.name !== "string" || !args.name.trim()) throw new Error("name is required: use a skill name returned by search");
  if (args.file !== undefined && (typeof args.file !== "string" || !args.file)) throw new Error("file must be a listed Markdown filename");
  return { name: args.name, file: typeof args.file === "string" ? args.file : "SKILL.md" };
}

export function readSkill(data: string, workspace: string | undefined, name: string, file: string): string {
  const catalog = memory(data, workspace);
  const skill = catalog.skills.find((s: any) => s.name === name);
  if (!skill) throw new Error(`No skill ${JSON.stringify(name)} in this workspace on this station`);
  const text = file === "SKILL.md" ? skill.text : skill.files.find((f: any) => f.name === file)?.text;
  if (typeof text !== "string") throw new Error(`No file ${JSON.stringify(file)} in skill ${JSON.stringify(name)}; read SKILL.md for the available files`);
  const files = ["SKILL.md", ...skill.files.map((f: any) => f.name)];
  return `Skill ${JSON.stringify(name)}, file ${JSON.stringify(file)}\nAvailable files: ${files.map((f) => JSON.stringify(f)).join(", ")}\n\n${text}`;
}

export async function skillForPeer(data: string, request: any, workspace: string | null, home: string | null): Promise<{ text: string }> {
  const { name, file } = selection(request ?? {});
  return { text: readSkill(data, workspace === null || workspace === home ? undefined : workspace, name, file) };
}

export function skillTools(deps: SearchDeps): Tool[] {
  return [{
    name: "skill_read",
    description: "Read a skill found by search in full, on this station or another station of the same workspace. Use its exact name and station from the search result. With file, read one of the Markdown reference filenames listed in the reply. Reads only this workspace's skill catalog; does not install, share or execute the skill. Another station must support skill.read; a refused call reports its error.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "The exact skill name from search." },
        station: { type: "string", description: "The station's id or unique name from search. Omit for this station." },
        file: { type: "string", description: "A Markdown filename listed by this skill (default SKILL.md)." },
      },
      required: ["name"],
      additionalProperties: false,
    },
    run: async (session, args) => {
      const { name, file } = selection(args);
      const place = deps.workspaceOf(session);
      if (!place) throw new Error("unknown session");
      const only = typeof args.station === "string" ? args.station.trim().toLowerCase() : "";
      if (!only || only === "this station") return deps.readSkill(place.home ? undefined : place.workspace, name, file);
      const stations = await deps.stations(place.workspace);
      const chosen = stations.filter((s) => s.id.toLowerCase() === only || s.name.toLowerCase() === only);
      if (chosen.length !== 1) throw new Error(chosen.length ? "Station name is ambiguous; use the station id from search" : "No such station in this workspace");
      const station = chosen[0]!;
      if (station.here) return deps.readSkill(place.home ? undefined : place.workspace, name, file);
      const answer = await wall.within(20_000, deps.ask(station.id, { method: SKILL_READ, workspace: place.workspace, session, name, file }), "Station did not answer skill.read within 20 s");
      if (typeof answer?.text !== "string") throw new Error("Station did not return a skill; it may need an update to support skill.read");
      return answer.text;
    },
  }];
}
