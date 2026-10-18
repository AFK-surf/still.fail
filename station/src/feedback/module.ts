// Bug reports to the still.fail team as a part of the station (parts.ts): from stations on the stable channel
// (updates.rs `channel_of`), in still.fail cloud only (feedback is no part of the control plane: another provider's
// stations send none). The agents' tool to send one, and each session told when one it sent is fixed and out: a few
// minutes after the start and every hour (the cloud has no way to say so as it happens).
import { Effect, Layer } from "effect";
import { signedPost } from "../cloud/signed.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { version } from "../ops/version.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Key, Parts, Store } from "../services.ts";
import { feedbackTools, tellFixed } from "../tools/feedback.ts";

export const FeedbackLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const cloud = plane.state;
    const key = yield* Key;
    const store = yield* Store;
    const { updates, hub, pageOf } = yield* Agents;
    if (!(updates.channel() === "stable" && plane.spec().feedback)) return;
    const sendReport = async (report: any) => {
      if (cloud.removed()) throw new Error("this station was removed from its workspace");
      report.context = { ...(report.context ?? {}), version: version() };
      return signedPost(cloud, key, "/v1/feedback", "stillfail-station-feedback-v1", report);
    };
    const fixed = async (told: string[]) => {
      if (cloud.removed()) return { fixed: [] };
      return { ...(await signedPost(cloud, key, "/v1/feedback/fixed", "stillfail-station-feedback-fixed-v1", { told })), station: version() };
    };
    (yield* Parts).tools(feedbackTools(store, (k) => pageOf(k) ?? null, () => (cloud.state ? sendReport : null)));
    const tellingFixed = () =>
      void tellFixed(fixed, (session, text) => hub.notify(session, text)).catch((error) => log.warn("feedback", "fixed bug reports not read", { error: (error as Error).message }));
    // On the hub's clock, ended with the station.
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("feedback", hub.clock)), (t) => Effect.promise(() => t.close()));
    time.after(300_000, tellingFixed);
    time.every(3_600_000, tellingFixed);
  }),
);
