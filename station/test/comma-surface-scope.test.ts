import assert from "node:assert/strict";
import { test } from "node:test";
import { CommaSurface } from "../src/comma/surface.ts";

const message = { messages: [{ text: "synthetic private message" }] };
const request = { type: "request", id: "read", method: "task.read", params: { task: "1" } };
const socket = (sent: any[]) => ({ send: (data: string) => sent.push(JSON.parse(data)) });
const surface = (read: () => Promise<any>, inScope: () => boolean) => new CommaSurface({
  connect: "one", server: "http://127.0.0.1", token: "test", name: "one",
  tasks: {} as never, store: {} as never, models: () => [],
  chats: { read, say: async () => ({}) }, inScope,
});
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

test("a workspace change after the Router read completes is checked before its reply", async () => {
  let allowed = true, checks = 0;
  const sent: any[] = [];
  const sock = socket(sent);
  const s = surface(async () => message, () => {
    if (++checks === 2) queueMicrotask(() => { allowed = false; });
    return allowed;
  });
  (s as any).socket_ = sock;
  (s as any).frame(sock, request, () => {});
  await tick();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].type, "error");
  assert.equal(JSON.stringify(sent).includes("synthetic private message"), false);
});

test("a Router read in an unchanged workspace replies normally", async () => {
  const sent: any[] = [];
  const sock = socket(sent);
  const s = surface(async () => message, () => true);
  (s as any).socket_ = sock;
  (s as any).frame(sock, request, () => {});
  await tick();
  assert.deepEqual(sent, [{ id: "read", type: "response", result: message }]);
});

for (const fails of [false, true]) {
  test(`an old socket's ${fails ? "failed" : "completed"} Router read is not sent to its replacement`, async () => {
    const oldSent: any[] = [], newSent: any[] = [];
    const old = socket(oldSent), replacement = socket(newSent);
    let finish!: () => void;
    const gate = new Promise<void>((resolve) => { finish = resolve; });
    const s = surface(async () => { await gate; if (fails) throw new Error("read failed"); return message; }, () => true);
    (s as any).socket_ = old;
    (s as any).frame(old, request, () => {});
    (s as any).socket_ = replacement;
    finish();
    await tick();
    assert.deepEqual(oldSent, []);
    assert.deepEqual(newSent, []);
  });
}
