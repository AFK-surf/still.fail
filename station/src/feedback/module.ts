// Bug reports to the still.fail team as a part of the station (parts.ts): from stations on the stable channel
// , in still.fail cloud only (feedback is no part of the control plane: another provider's
// stations send none). The agents' tools to send one and to answer on one, and each session told when one it sent is
// fixed and out: a few minutes after the start, then as each release is out. The team's replies on one are not the
// station's: people read them in the app, from the cloud. A failure notice in a chat
// reported by a person (its 上报, feedback/notice.ts), and the overview's `feedback` saying the station takes them.
import { homedir } from "node:os";
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { signedPost } from "../cloud/signed.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { version } from "../ops/version.ts";
import { Agents } from "../sessions/agents.ts";
import { agentEnv } from "../ops/agent-env.ts";
import { ControlPlane, Key, Parts, Paths, Store } from "../services.ts";
import { feedbackTools, tellFixed } from "../tools/feedback.ts";
import { REPORT_PATH, readTail, reportRoutes } from "./notice.ts";

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
      // The workspace its chat is in (a joined one's, else the home's): where the team's replies are shown.
      const session = typeof report.context?.session === "string" ? store.getSession(report.context.session) : null;
      const workspace = session?.ws ?? cloud.state?.workspace;
      report.context = { ...(report.context ?? {}), version: version(), ...(workspace ? { workspace } : {}) };
      return signedPost(cloud, key, "/v1/feedback", "stillfail-station-feedback-v1", report);
    };
    const fixed = async (told: string[]) => {
      if (cloud.removed()) return { fixed: [] };
      return { ...(await signedPost(cloud, key, "/v1/feedback/fixed", "stillfail-station-feedback-fixed-v1", { told })), station: version() };
    };
    const answer = async (body: unknown) => {
      if (cloud.removed()) throw new Error("this station was removed from its workspace");
      return signedPost(cloud, key, "/v1/feedback/reply", "stillfail-station-feedback-reply-v1", body);
    };
    const parts = yield* Parts;
    const { data } = yield* Paths;
    parts.tools(feedbackTools(store, (k) => pageOf(k) ?? null, () => (cloud.state ? sendReport : null), () => (cloud.state ? answer : null)));
    parts.routes(reportRoutes(store, {
      logTail: (most) => readTail(join(data, "stillfail.log"), most),
      versions: () => Object.fromEntries(updates.get("en").flatMap((v) => (v.installed && v.version ? [[v.id, v.version]] : []))),
      envNames: () => Object.keys(agentEnv()).sort(),
      link: (k) => pageOf(k) ?? null,
      home: process.env.HOME ?? homedir(),
    }, sendReport));
    // Reporting changes nothing on the station: a read-only member may.
    parts.viewerMay((r) => r.method === "POST" && REPORT_PATH.test(r.path));
    parts.overview("feedback", () => cloud.state !== null);
    const tellingFixed = () =>
      void tellFixed(fixed, (session, text) => hub.notify(session, text)).catch((error) => log.warn("feedback", "fixed bug reports not read", { error: (error as Error).message }));
    // What was fixed and came out while the station was not running, a while after it starts; then as each release is
    // out (a fix is out only with one). On the hub's clock, ended with the station.
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("feedback", hub.clock)), (t) => Effect.promise(() => t.close()));
    time.after(300_000, tellingFixed);
    plane.told("release", tellingFixed);
  }),
);
