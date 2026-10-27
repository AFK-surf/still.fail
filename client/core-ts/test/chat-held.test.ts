// A chat's files whose pictures this device keeps (AccountDb.file_kept: an image's thumbnail, a video's still): its
// view says so (`held`, views.ts drawn), through the shape it is sent in (shapes/schema.ts Attachment), so the app's
// first page waits for them as for the rest of what it shows; one not kept says nothing.
import assert from "node:assert/strict";
import { test } from "node:test";
import { call, subscribe } from "./helpers.ts";
import { base, started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const reply = { thread: 7, n: 1, kind: "message", target: null, ts: "1.0", authorKind: "agent", author: "k1", text: "两张图", at: 1, attachments: [{ name: "a.png", path: "/w/k1/a.png", size: 3 }, { name: "b.png", path: "/w/k1/b.png", size: 3 }] };

test("a_chats_files_whose_pictures_the_device_keeps_say_so_in_its_view", async () => {
  const answers = { ...base(), "GET /threads/7/entries?limit=50": { last: 1, entries: [reply] }, "GET /sessions/k1/files?name=a.png&thumb=1": "small" };
  const { host, core } = await started(answers);
  const ui = core.connect();
  // a.png's thumbnail asked once (kept on the device as it comes), b.png's never
  call(core, ui, 1, "station.file", { station: "ws/st", key: "k1", name: "a.png", thumb: true });
  await host.settle();
  subscribe(core, ui, 2, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  await host.settle();
  const value = host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === 2 && "value" in m).at(-1)?.value;
  const files = value?.messages?.find((m: J) => m.seq === 1)?.attachments ?? [];
  assert.deepEqual(files.map((f: J) => [f.name, f.owner, f.held]), [["a.png", "k1", true], ["b.png", "k1", undefined]]);
  core.close();
});
