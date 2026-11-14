// What a command is given besides its flags: an enrol token (43 characters of base64url) can begin with `-` or `--`,
// and taken for a flag it was dropped, the copied command refused with its usage (2026-11-14).
import assert from "node:assert/strict";
import { test } from "node:test";
import { positionals } from "../src/ops/files.ts";

const VALUED = ["--data", "--provider", "--lock", "--rig", "--workspace"];
const ORIGIN = "https://app.still.fail";

test("an enrol token beginning with - or -- is the token, wherever the flags are", () => {
  for (const token of ["--NS_e6ccHLMKlarzr5YZUZdokGGKrv4YRqSgaZdjC4", "-abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123456", "--abcdefghijklmnopqrstuvwxyzabcdefghijklmn"]) {
    assert.deepEqual(positionals(["enroll", ORIGIN, token], VALUED), ["enroll", ORIGIN, token], token);
    // as the installers run it, and with every flag around it
    assert.deepEqual(positionals(["enroll", ORIGIN, token, "--stay", "--lock", "a".repeat(64), "--rig", "b".repeat(64)], VALUED), ["enroll", ORIGIN, token]);
    assert.deepEqual(positionals(["--data", "/d", "enroll", "--join", ORIGIN, "--provider", "comma", token], VALUED), ["enroll", ORIGIN, token]);
    // after a bare --, everything as it is
    assert.deepEqual(positionals(["enroll", "--stay", "--", ORIGIN, token], VALUED), ["enroll", ORIGIN, token]);
  }
});

test("the flags are still flags, and what a valued one takes is its value", () => {
  assert.deepEqual(positionals(["lock", "reset", "--workspace", "01ABC"], VALUED), ["lock", "reset"]);
  assert.deepEqual(positionals(["enroll", ORIGIN, "tok", "--with-parent", "--launcher-pipe"], VALUED), ["enroll", ORIGIN, "tok"]);
  assert.deepEqual(positionals(["status"], VALUED), ["status"]);
});
