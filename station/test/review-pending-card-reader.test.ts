import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { DEFAULT_POLICY } from "../src/sessions/archive-policy.ts";
import { fingerprint } from "../src/sessions/decision.ts";
import { review } from "../src/sessions/review.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

test("an archive review reads its pending card without holding the station's store", async () => {
  const r = new Rig();
  let evidence: any = null;
  const server = createServer((req, res) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (part) => { body += part; });
    req.on("end", () => {
      evidence = JSON.parse(JSON.parse(body).state);
      const probabilities = { ...Object.fromEntries(DEFAULT_POLICY.options.map((o) => [o.id, 0.005])), answered: 0.96, awaiting_review: 0.01 };
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ model: "test-jev", answers: { decision: { type: "choice", probabilities } } }));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const m = say("<@UBOT> can you check this?");
    await r.accept(m);
    await settle();
    const key = `cl:C1:${m.threadTs}`, thread = r.thread("C1", m.threadTs);
    r.store.insertMessage({ thread: thread.id, ts: "9000.0001", authorKind: "agent", author: key, text: "original request",
      card: { type: "options", options: [{ label: "Yes" }] } });
    r.store.editMessage(thread.surface, thread.channel, thread.threadTs, "9000.0001", "edited request");
    const pending = r.store.pendingCard(thread.id);
    assert.equal(pending?.[0].text, "edited request");
    const endpoint = `http://127.0.0.1:${(server.address() as AddressInfo).port}/v1`;
    r.edit((raw) => {
      raw.automaticDecisions = { completion: { enabled: true, model: "test-jev" } };
      raw.profiles[0].env = { TYPESAFE_API_KEY: "profile-test-key", TYPESAFE_BASE_URL: endpoint };
    });
    const profile = r.config.profiles[0]!;
    const capability = { state: "ready", detail: "test", model: "test-jev", provider: "jev", fingerprint: fingerprint(profile), models: ["test-jev"] };
    r.hub.accounts.setHealth((id) => id === profile.id ? { check: { decision: capability, state: "ok", detail: "", models: null, checkedAt: 0 } } : {});
    (r.hub as any).reviewPendingCard = async (id: number) => { assert.equal(id, thread.id); return pending; };
    r.store.pendingCard = () => { throw new Error("station card lookup used"); };
    await review(r.hub, key);
    assert.deepEqual(evidence?.conversations?.[0]?.pendingCard, { ts: "9000.0001", text: "edited request" });
  } finally { server.close(); await r.close(); }
});
