import assert from "node:assert/strict";
import { test } from "node:test";
import { pickAttachment } from "../web/src/pickAttachment.ts";

test("first selection, cancellation, and selecting the same photo again release the attached picker", (t) => {
  const nodes: any[] = [];
  const attached = new Set();
  const doc = {
    createElement() {
      const input = {
        files: null as any, onchange: null as any, oncancel: null as any,
        setAttribute() {},
        click() { assert.ok(attached.has(this)); },
        remove() { attached.delete(this); },
      };
      nodes.push(input);
      return input;
    },
    body: { append(node: any) { attached.add(node); } },
  };
  Object.defineProperty(globalThis, "document", { value: doc, configurable: true });
  t.after(() => Reflect.deleteProperty(globalThis, "document"));
  const received: FileList[] = [];
  const photo = [new File(["photo"], "photo.jpg", { type: "image/jpeg" })];
  for (let i = 0; i < 3; i++) {
    pickAttachment("image/*", false, (files) => received.push(files));
    const input = nodes[i];
    assert.equal(attached.size, 1);
    if (i === 1) input.oncancel();
    else { input.files = photo; input.onchange(); }
    assert.equal(attached.size, 0);
    assert.equal(input.onchange, null);
    assert.equal(input.oncancel, null);
  }
  assert.equal(received.length, 2);
  assert.equal(received[0], photo);
  assert.equal(received[1], photo);
});
