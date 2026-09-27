import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { test } from "node:test";
import { fileCredentials } from "../src/no-keychain.ts";

test("on macOS a profile's processes find a security that holds nothing, so Claude Code keeps its login in the file", { skip: process.platform !== "darwin" }, () => {
  const env = fileCredentials({ PATH: "/usr/bin:/bin", HOME: "/nowhere" });
  const first = env.PATH.split(":")[0]!;
  assert.notEqual(first, "/usr/bin");
  let code = 0;
  try {
    execFileSync(join(first, "security"), ["find-generic-password", "-s", "x", "-w"]);
  } catch (error) {
    code = (error as { status: number }).status;
  }
  assert.equal(code, 44);
});
