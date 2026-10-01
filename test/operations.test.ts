import assert from "node:assert/strict";
import { test } from "node:test";
import { bindStationOperations, bindCloudOperations } from "../web/src/core/operations.ts";
import { CoreClient, callDetails, captureCall } from "../web/src/core/client.ts";

test("generated bindings preserve explicit null, omission and target identities", async () => {
  const sent: { name: string; params: Record<string, unknown> }[] = [];
  const call = async (name: string, params: Record<string, unknown>) => { sent.push({ name, params }); return { ok: true }; };
  const station = bindStationOperations(call);
  await station.sessionSettings({ key: "k", profile: null, model: "m" });
  assert.deepEqual(sent[0], { name: "session.settings", params: { key: "k", profile: null, model: "m" } });
  assert.equal(Object.hasOwn(sent[0]!.params, "effort"), false);
  await station.connectBindSession({ connect: "c", session: null });
  assert.deepEqual(sent[1]!.params, { connect: "c", session: null });
  await bindCloudOperations(call).workspaceAddMembers({ workspace: "w", role: "member", emails: ["a@x.test"] });
  assert.deepEqual(sent[2], { name: "workspace.addMembers", params: { workspace: "w", role: "member", emails: ["a@x.test"] } });
  // These are type assertions only, checked by tsgo without sending invalid calls.
  if (false) {
    // @ts-expect-error key is required
    void station.sessionStop({});
    // @ts-expect-error no route strings or arbitrary fields in the generated binding
    void station.sessionStop({ key: "k", path: "/stop" });
  }
});

test("action adapters identify wrapped core calls without retaining secrets or matching unrelated actions", async () => {
  let reply!: (message: unknown) => void;
  const sent: { id: number }[] = [];
  const client = new CoreClient((onMessage) => {
    reply = onMessage;
    return { post: (message) => sent.push(message as { id: number }), close() {} };
  });
  const ops = bindStationOperations((name, params) => client.call(name, { ...params, station: "w/s" }));
  const a = captureCall(() => ops.connectPut({ id: "a", input: { slack: { appToken: "secret" } } }).then(() => "done"));
  const b = captureCall(() => ops.connectDelete({ id: "b" }));
  assert.deepEqual(a.details, { name: "connect.put", on: { id: "a", station: "w/s" }, tracked: true });
  assert.deepEqual(b.details?.on, { id: "b", station: "w/s" });
  assert.deepEqual(callDetails(b.promise), b.details);
  reply({ id: sent[0]!.id, ok: {} }); reply({ id: sent[1]!.id, ok: {} });
  assert.equal(await a.promise, "done"); await b.promise;
  const secret = client.call("slack.verify", { station: "w/s", appToken: "xapp-secret", botToken: "xoxb-secret" });
  assert.deepEqual(callDetails(secret)?.on, { station: "w/s" });
  reply({ id: sent[2]!.id, ok: {} }); await secret;
  assert.equal(captureCall(() => Promise.resolve("native")).details, undefined);
  client.close();
});
