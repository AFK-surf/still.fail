// The connects' Slack as a part of the agents' side (connects/part.ts says what every platform's connects are there):
// the overview's connects and Slack workspaces, and the Slack routes.
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/slack.ts";
import { connectsPart } from "../connects/part.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { Events, Parts, Paths, StationConfig, Store } from "../services.ts";
import { makeConnections } from "./index.ts";

export const SlackLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const events = yield* Events;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const slack = yield* connectsPart(makeConnections, (s) => {
      if (s.connects().length === 0) log.warn("station", "no connect is connected; add or enable one in the workspace's settings");
    });
    agents.slackView({
      connection: (c: any) => slack.state(c.id),
      teams: (viewer) => slack.overview(viewer.email).slackTeams,
      apps: (viewer) => slack.overview(viewer.email).slackApps,
    });
    parts.routes(
      routes({
        slack, config, data, store,
        hub: () => agents.hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
        overviewChanged: () => events.overviewChanged(),
      }),
    );
  }),
);
