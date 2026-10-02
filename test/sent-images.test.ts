import assert from "node:assert/strict";
import { test } from "node:test";
import { keepSentImage, sentImage } from "../web/src/sentImages.ts";

test("a sent preview survives the staged-to-session move, stays station-scoped, and expires", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const revoked = t.mock.method(URL, "revokeObjectURL");
  keepSentImage("workspace/station", "/staged/unique-image.png", new Blob(["image"]));
  const url = sentImage("workspace/station", "/session/uploads/unique-image.png");
  assert.ok(url);
  assert.equal(sentImage("another/station", "/session/uploads/unique-image.png"), undefined);
  assert.equal(sentImage("workspace/station", "/session/uploads/different-image.png"), undefined);
  t.mock.timers.tick(60_000);
  assert.equal(sentImage("workspace/station", "/session/uploads/unique-image.png"), undefined);
  assert.equal(revoked.mock.calls[0]?.arguments[0], url);
});

test("a burst of sent previews releases the oldest image instead of keeping large blobs indefinitely", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const revoked = t.mock.method(URL, "revokeObjectURL");
  for (let i = 0; i < 21; i++) keepSentImage("s", `/staged/${i}-same-name.png`, new Blob([`${i}`]));
  assert.equal(sentImage("s", "/uploads/0-same-name.png"), undefined);
  assert.ok(sentImage("s", "/uploads/20-same-name.png"));
  assert.equal(revoked.mock.callCount(), 1);
  t.mock.timers.tick(60_000);
  assert.equal(revoked.mock.callCount(), 21);
});
