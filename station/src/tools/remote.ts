// The agents' tools for other stations of the workspace (the Rust station's remote.rs `Remote::tools`): station_list,
// station_task, station_file (once the Rust's, word for word; station_task has since taken `dir` and `back`); what they
// do is Remote.tool.
import type { Remote } from "../jobs/remote.ts";
import type { Tool } from "./mcp.ts";

export const STATION_TOOLS: { name: string; description: string; inputSchema: unknown }[] = [
  {
    name: "station_list",
    description:
      "List stations in this workspace with how busy each is and what it has, to pick where station_task runs: cores, arch/OS, GPU, CPU busy over about the last minute, load average, free memory, free disk where tasks run, running remote tasks/jobs/services/agent turns, relay ping. All are asked at once; one not answering within 2 s is listed offline, an older station's load is unknown. With station, the same for that one in detail, with whether it accepts tasks and file limits. Choose by the numbers: prefer an idle station with enough free memory and disk and the right OS/architecture; keep heavy builds and tests off small VMs. A station queues tasks itself when it is busy (station_task start says so): there are no locks between agents, so never wait for, ask for or announce one; start the task and the station runs it when there is room.",
    inputSchema: { type: "object", properties: { station: { type: "string" } }, additionalProperties: false },
  },
  {
    name: "station_task",
    description:
      "action mirrors lists this chat's synced directories on that station, including whether each is in use. action clean with mirror set to one listed name asks the station to remove it; a running or syncing mirror cannot be removed. It deletes everything in that mirror, including task outputs and changed files not brought back: save what is needed and choose only an unused, rebuildable mirror. If clean answers pending, repeat it with the same station and mirror until it answers; the removal continues in the meantime. A later task syncs it again. " +
      "Run a shell task on another station of this workspace. All tasks of this session run in one persistent directory there (shared, so a later task can build in what an earlier one cloned); keep checkouts and build output inside it, not elsewhere on that machine. It is removed, with anything still running, when this chat is archived or deleted, or after 14 days unused. action prepare records command/name with a caller-chosen stable key; upload inputs with station_file; action start executes it once. With dir (an absolute path of a directory here), each start first syncs it to a mirror there (its name is in prepare's answer, inside this session's directory): Git's tracked and untracked-not-ignored files (elsewhere all but node_modules/target/dist and the like), sending only what changed; the mirror's build output stays, unchanged files keep their mtime. A sync that takes longer than about 40 s answers syncing: true and goes on: call start again with the same key, which waits on that sync instead of beginning another. The command runs in the mirror, one task at a time per mirror; the station queues it when needed: start and get return its place, blocker, the queue’s CPU sample and memory pressure, and the measured machine load (CPU, memory, disk, checkedAt), or why the measurement is unavailable; sampling is not a busy CPU. It starts it by itself when there is room, one by one as the CPUs and memory allow, telling it how many CPUs are free (STILLFAIL_CPUS, MAKEFLAGS, CARGO_BUILD_JOBS) when others run; the screen (windows, GUI tests, simulators, screenshots) is one task's at a time, for work done in minutes: run just what uses it as `stillfail-job screen <command>` (it waits while another task has the screen and gives it back when that command ends, the rest of the task running beside the others'; scripts that know they open windows may do so themselves), or give screen: true at prepare to have it for the whole task; a window put up for a person and left there (a virtual machine, a simulator to look at) is `stillfail-job show <command>`, which waits for the screen to be free and then holds nothing; no task gets the screen while a person uses the machine, and one waiting is told who has it (queue.holder). Nothing is stopped for using much memory (you are told); only when the machine is about to run out is the largest of what the agents run there stopped, and you are told why; synced files it changed come back as a patch to review (never applied here). back: paths relative to where the command runs, downloaded when it ends into station-back/<key> of this workspace. Reuse the same key after uncertain replies; use a new key for new work. get/log/stop address the same task. Completion and job notices return here, including after reconnect/restart. Commands run as the remote station OS user, not in a sandbox. A lost process is marked failed with unknown exit, never automatically re-executed.",
    inputSchema: {
      type: "object",
      properties: {
        station: { type: "string" },
        key: { type: "string" },
        action: { enum: ["prepare", "start", "get", "log", "stop", "list", "mirrors", "clean"] },
        mirror: { type: "string", description: "Name returned by action mirrors; action clean removes this one mirror." },
        command: { type: "string" },
        name: { type: "string" },
        lines: { type: "integer" },
        dir: { type: "string" },
        back: { type: "array", items: { type: "string" } },
        screen: { type: "boolean" },
      },
      required: ["station", "action"],
      additionalProperties: false,
    },
  },
  {
    name: "station_file",
    description:
      "Upload an input before starting a remote task, or download a task artifact to this session. path is relative to this session's directory on that station; local is a path in this session workspace. Files are transferred in chunks, up to 1 GiB each; repeat upload after a disconnect. direction is upload/download. Downloads never overwrite an existing local file. Post downloaded artifacts using chat_post files.",
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
