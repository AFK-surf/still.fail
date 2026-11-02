// The agents' home as a part of the station (parts.ts, sessions/agent-home.ts): the station's own skills written into
// each workspace's, and what stations before this one linked into the profiles' homes (the home workspace's memory and
// skills, which a joined workspace's sessions got too) taken away, at the start and again whenever the config changes
// (a profile added or moved). At the start and at each change of the config too, every home's transcripts are put in
// each runtime's one shared place (`linkTranscripts`).
// stillfail-feedback goes with the feedback_send tool (feedback/module.ts): stable channel, still.fail cloud.
import { Effect, Layer } from "effect";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { agentHomes, linkTranscripts, unlinkAgentHome, writeBuiltinSkills } from "../sessions/agent-home.ts";
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
        for (const home of agentHomes(agentHome)) writeBuiltinSkills(home, feedback);
        unlinkAgentHome(agentHome, profiles);
      } catch (error) {
        log.warn("agent_home", "the agents' home not kept", { error: (error as Error).message });
      }
    };
    const transcripts = () => {
      const { dataDir, profiles } = hub.config();
      try {
        linkTranscripts(dataDir, profiles);
      } catch (error) {
        log.warn("agent_home", "the shared transcripts not linked", { error: (error as Error).message });
      }
    };
    keep();
    transcripts();
    const unlisten = config.listen(() => {
      keep();
      transcripts();
    });
    yield* Effect.addFinalizer(() => Effect.sync(unlisten));
  }),
);
