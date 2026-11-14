import assert from "node:assert/strict";
import { test } from "node:test";
import { pastedSecret, randomSecret } from "../src/auth.ts";

// An enrollment's token is pasted after a command: one beginning with `-` was taken for an option (2026-11-14).
test("a secret pasted after a command never begins with -: one that does is drawn again", () => {
  const drawn = ["-NS_e6ccHLMKlarzr5YZUZdokGGKrv4YRqSgaZdjC4", "--S_e6ccHLMKlarzr5YZUZdokGGKrv4YRqSgaZdjC4", "NS_e6ccHLMKlarzr5YZUZdokGGKrv4YRqSgaZdjC4-"];
  let at = 0;
  assert.equal(pastedSecret(() => drawn[at++]!), drawn[2]);
  assert.equal(at, 3, "drawn until one does not");
  for (let i = 0; i < 2000; i++) {
    const secret = pastedSecret();
    assert.ok(!secret.startsWith("-"), secret);
    assert.equal(secret.length, randomSecret().length, "the same length as any secret");
  }
});
