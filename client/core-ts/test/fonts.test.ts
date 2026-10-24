// The faces a device's pages are set in (src/fonts.ts, docs/fonts.md): each place's as chosen, whole as it goes out,
// text as ui's until it is chosen, one installed on the device by its family; a face not there refused.
import assert from "node:assert/strict";
import { test } from "node:test";
import { answers, apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

test("each place's face is as chosen, whole as it goes out; text is ui's until chosen; one not there is refused", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  let faces = v(values, 1).faces;
  // None chosen: the app's own everywhere.
  assert.deepEqual([faces.ui.id, faces.text.id, faces.code.id], ["", "", ""]);
  assert.equal(faces.code.mono, true);
  assert.deepEqual(faces.list.map((f: any) => f.id), ["inter", "noto-sans-sc", "noto-serif-sc", "lxgw-wenkai", "jetbrains-mono", "fira-code", "maple-mono"]);
  assert.deepEqual(faces.list.filter((f: any) => f.mono).map((f: any) => f.id), ["jetbrains-mono", "fira-code", "maple-mono"]);

  call(core, ui, 2, "prefs.set", { fonts: { ui: "noto-sans-sc", code: "local:Berkeley Mono" } });
  await host.settle();
  apply(host, values);
  const prefs = v(values, 1);
  faces = prefs.faces;
  assert.deepEqual(prefs.fonts, { ui: "noto-sans-sc", code: "local:Berkeley Mono" });
  assert.equal(faces.ui.name, "思源黑体");
  assert.equal(faces.ui.family, "SF Noto Sans SC");
  assert.match(faces.ui.css, /\/releases\/fonts\/noto-sans-sc\/2\.004\/font\.css$/);
  assert.equal(faces.ui.files.length, 1);
  assert.match(faces.ui.files[0].url, /\/releases\/fonts\/noto-sans-sc\/2\.004\/var\.ttf\.gz$/);
  assert.equal(faces.ui.bytes, faces.ui.files[0].bytes);
  // Its preview (the fonts page's characters alone), beside its files.
  assert.match(faces.ui.preview, /\/releases\/fonts\/noto-sans-sc\/2\.004\/preview-[0-9a-f]{8}\.ttf$/);
  // Text not chosen: as ui.
  assert.deepEqual(faces.text, faces.ui);
  assert.deepEqual([faces.code.id, faces.code.family, faces.code.files, faces.code.css], ["local:Berkeley Mono", "Berkeley Mono", [], undefined]);

  // One place at a time: the others stay; null goes back to the app's own.
  call(core, ui, 3, "prefs.set", { fonts: { text: "lxgw-wenkai", code: null } });
  await host.settle();
  apply(host, values);
  faces = v(values, 1).faces;
  assert.deepEqual([faces.ui.id, faces.text.id, faces.code.id], ["noto-sans-sc", "lxgw-wenkai", ""]);
  assert.deepEqual(faces.text.files.map((f: any) => f.weight), [400, 500]);

  // A face not there, or a place not there: refused, nothing changed.
  for (const [id, fonts] of [[4, { ui: "comic-sans" }], [5, { title: "inter" }], [6, { code: "local:" }]] as const) {
    call(core, ui, id, "prefs.set", { fonts });
    await host.settle();
    const answer = answers(host.takeEmitted(), id);
    assert.ok(answer && "error" in answer, JSON.stringify(answer));
  }
  call(core, ui, 7, "prefs.set", { fonts: { ui: null, text: null } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).fonts, {});
  assert.deepEqual(v(values, 1).faces.ui.id, "");
  core.close();
});

test("a place's face says where this device keeps each of its files, so the app reads them there as it starts", async () => {
  const kept = new Set<string>();
  const { host, core } = await started(undefined, 0, undefined, (s) => {
    s.host.storagePath = (key) => (kept.has(key) ? `/data/${key}` : null);
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  call(core, ui, 2, "prefs.set", { fonts: { text: "lxgw-wenkai" } });
  await host.settle();
  const values = new Map();
  apply(host, values);
  // none kept yet: no path
  assert.deepEqual(v(values, 1).faces.text.files.map((f: any) => f.path), [undefined, undefined]);
  // kept (an earlier run's): each file where it is, the faces not chosen saying none
  const [a, b] = v(values, 1).faces.text.files.map((f: any) => f.sha256);
  kept.add(`fonts/file/${a}`);
  kept.add(`fonts/file/${b}`);
  call(core, ui, 3, "prefs.set", { fonts: { text: "lxgw-wenkai", ui: "inter" } });
  await host.settle();
  apply(host, values);
  const faces = v(values, 1).faces;
  assert.deepEqual(faces.text.files.map((f: any) => f.path), [`/data/fonts/file/${a}`, `/data/fonts/file/${b}`]);
  assert.deepEqual(faces.ui.files.map((f: any) => f.path), [undefined]);
  assert.ok(faces.list.every((f: any) => f.files.every((x: any) => x.path === undefined)));
  core.close();
});
