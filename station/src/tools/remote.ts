// The agents' tools for other stations of the workspace: station_list,
// station_task, station_file (once the Rust's; station_task has since taken `dir` and `back`); what they do is
// Remote.tool. Their descriptions are held short (test/tools-weight.test.ts): the details are in
// src/skills/stillfail-jobs.md.
import type { Remote } from "../jobs/remote.ts";
import type { Tool } from "./mcp.ts";

export const STATION_TOOLS: { name: string; description: string; inputSchema: unknown }[] = [
  {
    name: "station_list",
    description:
      "List the stations of this workspace, and this station's sandboxes, with how busy each is and what it has (cores, arch/OS, GPU, CPU busy, load, free memory and disk, what it runs, relay ping), to pick where station_task runs. There are no locks between agents: never wait for, ask for or announce one; start the task and the station queues it when it must. One with mode: \"tasks\" only runs tasks and is its owner's: where it says this chat may not use it (thisChat), ask with station_use. One listed unprotected cannot be called from here and says why: not a bug, tell the person. Skill stillfail-jobs (Another station) says how to choose.",
    inputSchema: { type: "object", properties: { station: { type: "string", description: "One station, in detail, with whether it accepts tasks and its file limits." } }, additionalProperties: false },
  },
  {
    name: "station_task",
    description:
      "Run a shell task on another station of this workspace, or in a sandbox of this station's (station_list lists both). action prepare records command and name under a key you choose; upload inputs with station_file; action start runs it once, queued there when it must be, and you are told here when it ends. After an uncertain answer use the same key again; a new key is new work. On a station it runs as that station's OS user, not confined. All tasks of this session there share one directory, removed with anything still running when this chat is archived or deleted, or after 14 days unused: bring back what must last. With dir, each start first syncs that directory to a mirror there and runs the command in it; when start answers syncing: true, call start again with the same key. action clean deletes a mirror with everything in it, results not brought back included. Skill stillfail-jobs (Another station) says the rest: the queue, the screen, small tasks, mirrors, what comes back.",
    inputSchema: {
      type: "object",
      properties: {
        station: { type: "string" },
        key: { type: "string" },
        action: { enum: ["prepare", "start", "get", "log", "stop", "release", "list", "mirrors", "clean"], description: "get, log (lines) and stop address the task of key. release, on a task some of whose results could not be saved, lets another task use its mirror: keep them with station_file first. list, mirrors and clean need only station." },
        mirror: { type: "string", description: "Name returned by action mirrors; action clean removes this one mirror." },
        command: { type: "string" },
        name: { type: "string" },
        lines: { type: "integer" },
        dir: { type: "string", description: "prepare: an absolute path of a directory here, synced before each start (what Git tracks or would add, only what changed)." },
        back: { type: "array", items: { type: "string" }, description: "prepare: paths relative to where the command runs, downloaded when it ends into station-back/<key> of this workspace (removed once nothing in it changed for 6 hours: move what you keep)." },
        screen: { type: "boolean", description: "prepare: the task has the screen (windows, simulators) from start to end. For one command of it, run that as `stillfail-job screen <command>` instead." },
        small: { type: "boolean", description: "A brief one-CPU offscreen task (not a build, test suite, video or screen work)." },
      },
      required: ["station", "action"],
      additionalProperties: false,
    },
  },
  {
    name: "station_file",
    description:
      "Upload an input before starting a remote task, or download a task artifact to this session. path is relative to this session's directory on that station; local is a path in this session workspace. Files are transferred in chunks, up to 1 GiB each; repeat upload after a disconnect. Downloads never overwrite an existing local file. Post downloaded artifacts using chat_post files.",
    inputSchema: {
      type: "object",
      properties: {
        station: { type: "string" },
        key: { type: "string" },
        direction: { enum: ["upload", "download"] },
        path: { type: "string" },
        local: { type: "string" },
      },
      required: ["station", "key", "direction", "path", "local"],
      additionalProperties: false,
    },
  },
];

export function remoteTools(remote: Remote): Tool[] {
  return STATION_TOOLS.map((t) => ({
    ...t,
    run: async (session, args) => JSON.stringify((await remote.tool(t.name, session, args)) ?? null, null, 2),
  }));
}
