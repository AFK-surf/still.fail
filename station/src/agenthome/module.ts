// The agents' shared home as a part of the station (parts.ts, sessions/agent-home.ts): linked into every profile's
// home under the names its runtimes load (MEMORY.md as CLAUDE.md/AGENTS.md, skills/), and given the station's own
// skills, at the start and again whenever the config changes (a profile added, moved or given another runtime).
// stillfail-feedback goes with the feedback_send tool (feedback/module.ts): stable channel, still.fail cloud.
import { Effect, Layer } from "effect";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { linkAgentHome, writeBuiltinSkills } from "../sessions/agent-home.ts";
import { ControlPlane, StationConfig } from "../services.ts";

export const AgentHomeLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const config = yield* StationConfig;
    const { updates, hub } = yield* Agents;
    const feedback = updates.channel() === "stable" && plane.spec().feedback === true;
    const keep = () => {
      const { agentHome, profiles } = hub.config();
      try {
        linkAgentHome(agentHome, profiles);
        writeBuiltinSkills(agentHome, feedback);
      } catch (error) {
        log.warn("agent_home", "the agents' home not kept", { error: (error as Error).message });
      }
    };
    keep();
    const unlisten = config.listen(keep);
    yield* Effect.addFinalizer(() => Effect.sync(unlisten));
  }),
);
