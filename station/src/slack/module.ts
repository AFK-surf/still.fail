// The connects' Slack as a part of the agents' side (connects/part.ts says what every platform's connects are there):
// a Slack connect as the overview shows it and the pages edit it, the overview's Slack workspaces and apps, and the
// Slack routes.
import { Effect, Layer } from "effect";
import { routes, slackEntry } from "../api/routes/slack.ts";
import { connectsPart } from "../connects/part.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { Events, Parts, Paths, StationConfig, Store } from "../services.ts";
import { makeConnections, slackShown } from "./index.ts";

export const SlackLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const events = yield* Events;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const slack = yield* connectsPart(makeConnections, {
      kind: "slack",
      shown: (_, c) => slackShown(c),
      entry: slackEntry,
      taken: (s) => {
        if (s.connects().length === 0) log.warn("station", "no connect is connected; add or enable one in the workspace's settings");
      },
    });
    // The Slack workspaces a viewer can make apps in (a configuration token each), and the apps they made that wait for
    // a connect.
    parts.overview("slackTeams", (viewer) => slack.overview(viewer.email).slackTeams);
    parts.overview("slackApps", (viewer) => slack.overview(viewer.email).slackApps);
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
