// The agents' shared home as a part of the station (parts.ts, sessions/agent-home.ts): linked into every profile's
// home under the names its runtimes load (MEMORY.md as CLAUDE.md/AGENTS.md, skills/), and given the station's own
// skills, at the start and again whenever the config changes (a profile added, moved or given another runtime) or a
// skill comes or goes (a profile whose runtime keeps skills of its own takes the shared ones one by one).
// stillfail-feedback goes with the feedback_send tool (feedback/module.ts): stable channel, still.fail cloud.
import { type FSWatcher, watch } from "node:fs";
import { Effect, Layer } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { agentHomePaths, linkAgentHome, writeBuiltinSkills } from "../sessions/agent-home.ts";
import { ControlPlane, StationConfig } from "../services.ts";

/// How long the shared skills stay unchanged before the profiles are looked at again.
const SETTLE_MS = 1000;

export const AgentHomeLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const config = yield* StationConfig;
    const { updates, hub } = yield* Agents;
    const feedback = updates.channel() === "stable" && plane.spec().feedback === true;
    const keep = () => {
      const { agentHome, profiles } = hub.config();
      try {
        writeBuiltinSkills(agentHome, feedback);
        linkAgentHome(agentHome, profiles);
      } catch (error) {
        log.warn("agent_home", "the agents' home not kept", { error: (error as Error).message });
      }
    };
    keep();
    const unlisten = config.listen(keep);
    // A skill made, shared in or taken away: looked at once things settle (a skill is written a file at a time). On
    // the hub's clock, ended with the station.
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("agent_home", hub.clock)), (t) => Effect.promise(() => t.close()));
    let soon = () => {};
    let skills: FSWatcher | undefined;
    try {
      skills = watch(agentHomePaths(hub.config().agentHome)[1], () => {
        soon();
        soon = time.after(SETTLE_MS, keep);
      });
      skills.on("error", () => skills?.close());
    } catch (error) {
      log.warn("agent_home", "the shared skills not watched", { error: (error as Error).message });
    }
    yield* Effect.addFinalizer(() =>
      Effect.sync(() => {
        unlisten();
        skills?.close();
      }),
    );
  }),
);
