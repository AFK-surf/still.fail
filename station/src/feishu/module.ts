// The Feishu connects as a part of the agents' side (docs/feishu.md; connects/part.ts says what every platform's
// connects are there): the overview's Feishu connects and the apps being made by a scan, the Feishu routes, and
// feishu_api for the agents.
import { Effect, Layer } from "effect";
import { feishuRoutes } from "../api/routes/feishu.ts";
import { connectsPart } from "../connects/part.ts";
import { Agents } from "../sessions/agents.ts";
import { Parts, Paths, StationConfig } from "../services.ts";
import { makeFeishu } from "./index.ts";
import { shownRegistration } from "./register.ts";
import { feishuTools } from "./tool.ts";

export const FeishuLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const config = yield* StationConfig;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const feishu = yield* connectsPart(makeFeishu);
    agents.connectView("feishu", { connection: (c: any) => feishu.state(String(c?.id ?? "")), shown: (c: any) => feishu.shown(c) });
    parts.overview("feishuRegistrations", (viewer) => feishu.registrations.of(viewer.email).map(shownRegistration));
    parts.routes(
      feishuRoutes({
        feishu, config, data,
        hub: () => agents.hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
      }),
    );
    const isFeishu = (connect: string) => feishu.connects().some((c) => c.id === connect);
    parts.tools(feishuTools(() => agents.hub, isFeishu));
  }),
);
